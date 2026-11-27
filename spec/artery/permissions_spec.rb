# frozen_string_literal: true

describe Artery::Permissions do
  let(:get_subscription) do
    instance_double(Artery::Subscription, uri: Artery::Routing.uri(model: :sources, action: :get),
                                          requested_routes: [])
  end
  let(:watch_subscription) do
    instance_double(Artery::Subscription, uri: Artery::Routing.uri(service: :bush, model: :user, action: '*'),
                                          requested_routes: %w[bush.users.get_updates bush.users.get])
  end
  let(:backend) { instance_double(Artery::Backends::NATSPure, inbox_prefix: '_INBOX.test') }

  before do
    stub_const('Artery::Check::ESSENTIAL_SERVICES', %w[billing])
    allow(Artery).to receive_messages(
      models: [class_double(Source, artery_source_model?: true, artery_model_name: :source),
               class_double(Recipient, artery_source_model?: false, artery_model_name: :recipient)],
      subscriptions: { get_subscription.uri => [get_subscription], watch_subscription.uri => [watch_subscription] },
      outgoing_routes: %w[license.licenses.daas_tokens test.healthz.check],
      backend: backend
    )
  end

  describe '#publish' do
    subject { described_class.new.publish }

    let(:routes) do
      %w[
        _INBOX.>
        billing.healthz.check
        bush.healthz.check
        bush.users.get
        bush.users.get_updates
        license.licenses.daas_tokens
        test.healthz.check
        test.source.*
      ]
    end

    it { is_expected.to eq(routes) }

    context 'with a subscription to every service' do
      let(:watch_subscription) do
        instance_double(Artery::Subscription, uri: Artery::Routing.uri(service: '*', model: :user, action: '*'),
                                              requested_routes: [])
      end

      it { is_expected.not_to include('*.healthz.check') }
    end

    context 'with an own inbox prefix outside _INBOX' do
      let(:backend) { instance_double(Artery::Backends::NATSPure, inbox_prefix: 'REPLIES.test') }

      it { is_expected.to include('_INBOX.>', 'REPLIES.test.>') }
    end
  end

  describe '#subscribe' do
    subject { described_class.new.subscribe }

    it { is_expected.to eq(%w[_INBOX.test.> bush.user.* test.healthz.check test.healthz.worker test.sources.get]) }

    context 'without inbox prefix' do
      let(:backend) { instance_double(Artery::Backends::NATSPure, inbox_prefix: nil) }

      it { is_expected.to include('_INBOX.>') }
    end
  end

  describe '#to_nats_user' do
    subject(:entry) { described_class.new.to_nats_user }

    it { is_expected.to include(%("user": "test"), %("password": $TEST_PASSWORD_HASH)) }

    it 'puts the routes into their sections', :aggregate_failures do
      expect(entry).to match(/"publish": \{\s*"allow": \[[^\]]*"test\.source\.\*"/)
      expect(entry).to match(/"subscribe": \{\s*"allow": \[[^\]]*"_INBOX\.test\.>"/)
    end

    context 'with a password variable' do
      subject { described_class.new.to_nats_user(password_variable: 'BILLING_NATS') }

      it { is_expected.to include(%("password": $BILLING_NATS)) }
    end

    context 'with a password variable that is not a variable name' do
      subject(:entry) { described_class.new.to_nats_user(password_variable: "PASSWORD\n}") }

      it 'refuses to print the entry' do
        expect { entry }.to raise_error(ArgumentError)
      end
    end

    context 'with a service name that is not a variable name' do
      before do
        allow(Artery).to receive(:service_name).and_return(:'kibana-elasticsearch')
      end

      it { is_expected.to include(%("password": $KIBANA_ELASTICSEARCH_PASSWORD_HASH)) }
    end

    context 'with a service name starting with a digit' do
      before do
        allow(Artery).to receive(:service_name).and_return(:'2fa')
      end

      it { is_expected.to include(%("password": $_2FA_PASSWORD_HASH)) }
    end

    context 'with a user name' do
      subject { described_class.new.to_nats_user(user: 'billing_nats') }

      it { is_expected.to include(%("user": "billing_nats")) }
    end
  end

  describe '#permits?' do
    let(:permissions) { described_class.new }

    # The permissions of a user; the tables below are what nats-server 2.14.10 allowed and denied it.
    before do
      allow(permissions).to receive_messages(publish: %w[exact.subject one.* tail.> mid.*.end *.lead],
                                             subscribe: %w[sub.exact sub.one.* sub.tail.> sub.*.mid])
    end

    context 'when it publishes' do
      subject { published.keys.to_h { |name| [name, permissions.permits?(:publish, name)] } }

      let(:published) do
        {
          'exact.subject' => true,
          'exact.subject.more' => false,
          'exact' => false,
          'one.a' => true,
          'one.a.b' => false,
          'one' => false,
          'tail.a' => true,
          'tail.a.b.c' => true,
          'tail' => false,
          'mid.x.end' => true,
          'mid.x.y.end' => false,
          'x.lead' => true,
          'a.b.lead' => false,
          'lead' => false,
          'exact.subject.' => false,
          'one.' => false,
          '.lead' => false,
          'tail..x' => false,
          'tail.a.' => false
        }
      end

      it { is_expected.to eq(published) }
    end

    context 'when a declared pattern is malformed' do
      subject do
        denied.keys.to_h do |name|
          [name, permissions.permits?(:publish, name)]
        end
      end

      let(:denied) do
        { 'orders.events.write' => false, 'orders.events.read' => false, 'orders.events' => false, '' => false }
      end

      before do
        allow(permissions).to receive(:publish).and_return(['orders.>.read', 'orders.events.', ''])
      end

      it { is_expected.to eq(denied) }
    end

    context 'when it subscribes' do
      subject { subscribed.keys.to_h { |name| [name, permissions.permits?(:subscribe, name)] } }

      let(:subscribed) do
        {
          'sub.exact' => true,
          'sub.one.a' => true,
          'sub.one.*' => true,
          'sub.one.>' => true,
          'sub.tail.a' => true,
          'sub.tail.*' => true,
          'sub.tail.>' => true,
          'sub.tail' => false,
          'sub.*' => false,
          'sub.>' => false,
          'sub.x.mid' => true,
          'sub.*.mid' => true,
          'sub.x.*' => false,
          'sub.exact.*' => false,
          'sub.*.*' => false,
          '>' => false
        }
      end

      it { is_expected.to eq(subscribed) }
    end
  end
end
