# frozen_string_literal: true

describe Artery::Permissions do
  let(:get_subscription) do
    instance_double(Artery::Subscription, uri: Artery::Routing.uri(model: :sources, action: :get), client?: false)
  end
  let(:synchronized_subscription) do
    instance_double(Artery::Subscription, uri: Artery::Routing.uri(service: :bush, model: :user, action: '*'),
                                          client?: true, synchronize?: true, synchronize_updates?: true,
                                          rewindable?: true)
  end
  let(:deletion_subscription) do
    instance_double(Artery::Subscription, uri: Artery::Routing.uri(service: :madison, model: :alert, action: :delete),
                                          client?: true, synchronize?: false, synchronize_updates?: false,
                                          rewindable?: false)
  end
  let(:backend) { instance_double(Artery::Backends::NATSPure, inbox_prefix: '_INBOX.test') }

  before do
    stub_const('Artery::Check::ESSENTIAL_SERVICES', %w[billing])
    allow(Artery).to receive_messages(
      models: [class_double(Source, artery_source_model?: true, artery_model_name: :source),
               class_double(Recipient, artery_source_model?: false, artery_model_name: :recipient)],
      subscriptions: {
        get_subscription.uri => [get_subscription],
        synchronized_subscription.uri => [synchronized_subscription],
        deletion_subscription.uri => [deletion_subscription]
      },
      outgoing_routes: %w[license.licenses.daas_tokens bush.users.get],
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
        bush.users.get_all
        bush.users.get_updates
        license.licenses.daas_tokens
        madison.healthz.check
        test.healthz.check
        test.source.*
      ]
    end

    it { is_expected.to eq(routes) }
  end

  describe '#subscribe' do
    subject { described_class.new.subscribe }

    let(:routes) do
      %w[_INBOX.test.> bush.user.* madison.alert.delete test.healthz.check test.healthz.worker test.sources.get]
    end

    it { is_expected.to eq(routes) }

    context 'without inbox prefix' do
      let(:backend) { instance_double(Artery::Backends::NATSPure, inbox_prefix: nil) }

      it { is_expected.to include('_INBOX.>') }
    end
  end

  describe '#to_nats_user' do
    subject { described_class.new.to_nats_user }

    it { is_expected.to include(%("user": "test"), %("password": $TEST_PASSWORD_HASH)) }

    context 'with a password variable' do
      subject { described_class.new.to_nats_user(password_variable: 'BILLING_NATS') }

      it { is_expected.to include(%("password": $BILLING_NATS)) }
    end

    context 'with a service name that is not a variable name' do
      before do
        allow(Artery).to receive(:service_name).and_return(:'kibana-elasticsearch')
      end

      it { is_expected.to include(%("password": $KIBANA_ELASTICSEARCH_PASSWORD_HASH)) }
    end
  end
end
