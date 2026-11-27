# frozen_string_literal: true

describe Artery::Backends::NATSPure, '#connect' do
  subject(:backend) { described_class.new({}) }

  let(:client) { backend.client }
  let(:server) { client.server_pool.first }

  before do
    allow(Artery).to receive(:handle_error)
    # Reconnecting would exit the calling thread, the one of RSpec, if the server errors reached nats-pure.
    allow(client).to receive(:process_op_error)
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
      backend.error_reporter.drain
    end

    it 'keeps the connection and the server', :aggregate_failures do
      expect(client).to be_connected
      expect(server).not_to include(:error_received)
      expect(client).not_to have_received(:process_op_error)
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
      backend.error_reporter.drain
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
      backend.error_reporter.drain
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
      backend.error_reporter.drain
    end

    it 'reports the denied subject without reconnecting', :aggregate_failures do
      expect(Artery).to have_received(:handle_error).with(reported_error)
      expect(client).not_to have_received(:process_op_error)
    end
  end

  context 'when the server denies a subject with a quote' do
    let(:reported_error) { having_attributes(artery_context: { subject: 'denied."quoted"' }) }

    before do
      client.send(:process_err, %('Permissions Violation for Publish to "denied.\\"quoted\\""'))
      backend.error_reporter.drain
    end

    it 'reports the subject as published' do
      expect(Artery).to have_received(:handle_error).with(reported_error)
    end
  end

  context 'when the server denies a subject with a backslash' do
    let(:reported_error) { having_attributes(artery_context: { subject: 'denied.back\\slash' }) }

    before do
      client.send(:process_err, %('Permissions Violation for Publish to "denied.back\\\\slash"'))
      backend.error_reporter.drain
    end

    it 'reports the subject as published' do
      expect(Artery).to have_received(:handle_error).with(reported_error)
    end
  end

  context 'when the error handler is slow' do
    # The thread is returned once it finishes, nil if it is still held after a second.
    subject do
      Thread.new { client.send(:process_err, %('Permissions Violation for Publish to "forbidden.thing"')) }.join(1)
    end

    let(:release) { Concurrent::Event.new }

    before do
      allow(Artery).to receive(:handle_error) { release.wait(5) }
    end

    after do
      release.set
    end

    it { is_expected.to be_a(Thread) }
  end

  context 'when the server rejects authentication' do
    before do
      client.send(:process_err, "'Authorization Violation'")
      backend.error_reporter.drain
    end

    it 'leaves the error to nats-pure' do
      expect(server).to include(error_received: true)
    end
  end

  context 'when nats-pure reports an authentication error' do
    before do
      client.send(:err_cb_call, client, NATS::IO::AuthError.new("'Authorization Violation'"), nil)
      backend.error_reporter.drain
    end

    it 'reports a backend error' do
      expect(Artery).to have_received(:handle_error).with(an_instance_of(Artery::BackendError))
    end
  end

  context 'when nats-pure reports a network error' do
    before do
      client.send(:err_cb_call, client, Errno::ECONNRESET.new, nil)
      backend.error_reporter.drain
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
      backend.error_reporter.drain
    end

    it 'logs the failure' do
      expect(Artery.logger).to have_received(:error).with(/Failed to report NATS error/)
    end
  end
end
