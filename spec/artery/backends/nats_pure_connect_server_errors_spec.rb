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
    subject(:reply) { client.request('artery.spec.echo', 'ping', timeout: 1).data }

    let(:entered) { Concurrent::Event.new }
    let(:release) { Concurrent::Event.new }

    before do
      # Reports the -ERR without reconnecting, on the thread that reads from the server.
      allow(client).to receive(:process_op_error) { |error| client.send(:err_cb_call, client, error, nil) }
      allow(Artery).to receive(:handle_error) { entered.set && release.wait(5) }
      client.subscribe('artery.spec.echo') { |message| message.respond(message.data) }
      client.subscribe('artery..invalid') { nil } # the server answers with -ERR 'Invalid Subject'
      entered.wait(2)
    end

    after do
      release.set
    end

    it 'replies while the error handler holds the error from the server', :aggregate_failures do
      expect(reply).to eq('ping')
      expect(entered).to be_set
    end
  end

  context 'when the server denies a subject with a quote and non-ASCII characters' do
    let(:reported_error) { having_attributes(artery_context: { subject: 'заказ."новый"' }) }

    before do
      client.send(:process_err, %('Permissions Violation for Publish to "заказ.\\"новый\\""').b)
      backend.error_reporter.drain
    end

    it 'reports the subject as published' do
      expect(Artery).to have_received(:handle_error).with(reported_error)
    end
  end

  context 'when the backend is connected again while a report is still running' do
    let(:release) { Concurrent::Event.new }
    let(:reported) { [] }

    before do
      stub_const('Artery::Backends::NATSPure::ErrorReporter::STOP_TIMEOUT', 0.1)
      allow(Artery).to receive(:handle_error) { |error| reported << error.message }
      allow(Artery).to receive(:handle_error).with(having_attributes(message: "NATS server error: 'First'")) do |error|
        release.wait(10)
        reported << error.message
      end
      client.send(:err_cb_call, client, NATS::IO::ServerError.new("'First'"), nil)
      backend.stop
      backend.connect
      client.send(:err_cb_call, client, NATS::IO::ServerError.new("'Second'"), nil)
      backend.error_reporter.drain(0.2) # a second queue would report 'Second' meanwhile
      release.set
      backend.error_reporter.drain
    end

    it 'reports the errors in order' do
      expect(reported).to eq(["NATS server error: 'First'", "NATS server error: 'Second'"])
    end
  end

  context 'when the backend is stopped with no report running' do
    let(:previous_reporter) { backend.error_reporter }

    before do
      allow(Artery.logger).to receive(:error)
      client.send(:err_cb_call, client, NATS::IO::ServerError.new("'First'"), nil)
      previous_reporter.drain
      backend.stop
      previous_reporter.post('late') { nil }
    end

    it 'shuts the reporter down' do
      expect(Artery.logger).to have_received(:error).with(/not reported, the reporter is shut down: late/)
    end
  end

  context 'when the backend is stopped while a report is still running' do
    let(:release) { Concurrent::Event.new }
    let(:previous_reporter) { backend.error_reporter }

    before do
      stub_const('Artery::Backends::NATSPure::ErrorReporter::STOP_TIMEOUT', 0.1)
      allow(Artery).to receive(:handle_error) { release.wait(10) }
      client.send(:err_cb_call, client, NATS::IO::ServerError.new("'First'"), nil)
      previous_reporter.drain(0.1)
      backend.stop
      release.set
    end

    it 'frees the reporting thread once the report is sent' do
      expect(previous_reporter.wait_for_termination(5)).to be(true)
    end
  end

  context 'when the backend is stopped and connected again' do
    let(:reported_error) { having_attributes(message: "NATS server error: 'Second'") }

    before do
      client.send(:err_cb_call, client, NATS::IO::ServerError.new("'First'"), nil)
      backend.stop
      backend.connect
      client.send(:err_cb_call, client, NATS::IO::ServerError.new("'Second'"), nil)
      backend.error_reporter.drain
    end

    it 'reports the errors that follow' do
      expect(Artery).to have_received(:handle_error).with(reported_error)
    end
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
