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
  let(:backend) { instance_double(Artery::Backends::NATSPure, inbox_prefix: '_INBOX.test', auth_user: nil) }

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
  end

  describe '#subscribe' do
    subject { described_class.new.subscribe }

    it { is_expected.to eq(%w[_INBOX.test.> bush.user.* test.healthz.check test.healthz.worker test.sources.get]) }

    context 'without inbox prefix' do
      let(:backend) { instance_double(Artery::Backends::NATSPure, inbox_prefix: nil, auth_user: nil) }

      it { is_expected.to include('_INBOX.>') }
    end
  end

  describe '#to_nats_user' do
    subject(:entry) { described_class.new.to_nats_user }

    it { is_expected.to include(%("user": "test"), %("password": $TEST_PASSWORD_HASH)) }

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

    context 'with a NATS user of password authentication' do
      let(:backend) { instance_double(Artery::Backends::NATSPure, inbox_prefix: nil, auth_user: 'billing_nats') }

      it { is_expected.to include(%("user": "billing_nats")) }
    end
  end
end
