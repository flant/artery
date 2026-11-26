# frozen_string_literal: true

describe Artery::Backends::NATSPure, '#connect' do
  subject(:backend) { described_class.new({}) }

  let(:client) { backend.client }
  let(:server) { client.server_pool.first }

  before do
    allow(Artery).to receive(:handle_error)
    # The test server runs without authentication; nats-pure decides by this flag how to treat -ERR.
    server[:auth_required] = true
  end

  after do
    client.close
  end

  context 'when the server denies a publish' do
    let(:route) { 'forbidden.thing' }
    let(:reported_error) { having_attributes(class: Artery::PermissionError, artery_context: { subject: route }) }

    before do
      client.send(:process_err, %('Permissions Violation for Publish to "forbidden.thing"'))
    end

    it 'keeps the connection and the server', :aggregate_failures do
      expect(client).to be_connected
      expect(server).not_to include(:error_received)
    end

    it 'reports the denied subject' do
      expect(Artery).to have_received(:handle_error).with(reported_error)
    end

    it 'keeps the error as the last one of the client' do
      expect(client.last_error).to be_a(NATS::IO::ServerError)
    end
  end

  context 'when the server denies a publish and the default error handler reports it' do
    before do
      allow(Artery).to receive(:handle_error).and_call_original
      allow(Artery.logger).to receive(:error)
      client.send(:process_err, %('Permissions Violation for Publish to "forbidden.thing"'))
    end

    it 'logs the error with its backtrace' do
      expect(Artery.logger).to have_received(:error).with(/\ANATS server error: 'Permissions Violation.*\n.+/m)
    end
  end

  context 'when the server denies a publish and an instrumentation subscriber fails' do
    before do
      allow(Artery::Instrumentation).to receive(:instrument).and_call_original
      allow(Artery::Instrumentation).to receive(:instrument)
        .with(:connection, hash_including(state: :error)).and_raise('subscriber failed')
      client.send(:process_err, %('Permissions Violation for Publish to "forbidden.thing"'))
    end

    it 'still reports the error' do
      expect(Artery).to have_received(:handle_error).with(an_instance_of(Artery::PermissionError))
    end
  end

  context 'when the server denies a subscription' do
    let(:inbox) { '_INBOX.other.>' }
    let(:reported_error) { having_attributes(class: Artery::PermissionError, artery_context: { subject: inbox }) }

    before do
      client.send(:process_err, %('Permissions Violation for Subscription to "_INBOX.other.>"'))
    end

    it 'reports the denied subject' do
      expect(Artery).to have_received(:handle_error).with(reported_error)
    end
  end

  context 'when the server rejects authentication' do
    before do
      # Stops nats-pure from reconnecting, which would exit the calling thread.
      allow(client).to receive(:process_op_error)
      client.send(:process_err, "'Authorization Violation'")
    end

    it 'leaves the error to nats-pure' do
      expect(server).to include(error_received: true)
    end
  end

  context 'when nats-pure reports an authentication error' do
    before do
      client.send(:err_cb_call, client, NATS::IO::AuthError.new("'Authorization Violation'"), nil)
    end

    it 'reports a backend error' do
      expect(Artery).to have_received(:handle_error).with(an_instance_of(Artery::BackendError))
    end
  end

  context 'when nats-pure reports a network error' do
    before do
      client.send(:err_cb_call, client, Errno::ECONNRESET.new, nil)
    end

    it 'leaves it to the disconnect and reconnect events' do
      expect(Artery).not_to have_received(:handle_error)
    end
  end

  context 'when the error handler fails' do
    before do
      allow(Artery).to receive(:handle_error).and_raise('error tracker is unavailable')
      allow(Artery.logger).to receive(:error)
      client.send(:err_cb_call, client, NATS::IO::ServerError.new("'Unknown Protocol Operation'"), nil)
    end

    it 'logs the failure' do
      expect(Artery.logger).to have_received(:error).with(/Failed to report NATS error/)
    end
  end
end
