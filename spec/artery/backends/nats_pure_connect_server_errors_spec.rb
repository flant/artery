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
    backend.stop
  end

  # Waits for the reports posted so far; the reporter takes no more afterwards.
  def wait_for_reports
    backend.error_reporter.tap(&:shutdown).wait_for_termination(5)
  end

  context 'when the server denies a publish' do
    let(:route) { 'forbidden.thing' }
    let(:reported_error) { having_attributes(class: Artery::PermissionError, artery_context: { subject: route }) }

    before do
      client.send(:process_err, %('Permissions Violation for Publish to "forbidden.thing"'))
      wait_for_reports
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
      wait_for_reports
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
      allow(Warning).to receive(:warn)
      client.send(:process_err, %('Permissions Violation for Publish to "forbidden.thing"'))
      wait_for_reports
    end

    it 'still reports the error without reconnecting', :aggregate_failures do
      expect(Artery).to have_received(:handle_error).with(an_instance_of(Artery::PermissionError))
      expect(client).not_to have_received(:process_op_error)
    end
  end

  context 'when the server denies a subscription' do
    let(:inbox) { '_INBOX.other.>' }
    let(:reported_error) { having_attributes(class: Artery::PermissionError, artery_context: { subject: inbox }) }

    before do
      client.send(:process_err, %('Permissions Violation for Subscription to "_INBOX.other.>"'))
      wait_for_reports
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
      wait_for_reports
    end

    it 'reports the subject as published' do
      expect(Artery).to have_received(:handle_error).with(reported_error)
    end
  end

  context 'when the server denies a subject with a backslash' do
    let(:reported_error) { having_attributes(artery_context: { subject: 'denied.back\\slash' }) }

    before do
      client.send(:process_err, %('Permissions Violation for Publish to "denied.back\\\\slash"'))
      wait_for_reports
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
      wait_for_reports
    end

    it 'reports the subject as published' do
      expect(Artery).to have_received(:handle_error).with(reported_error)
    end
  end

  context 'when the server denies a publish while the error handler is busy' do
    let(:release) { Concurrent::Event.new }

    before do
      allow(Artery.logger).to receive(:error)
      allow(Artery).to receive(:handle_error) { release.wait(5) }
      client.send(:process_err, %('Permissions Violation for Publish to "forbidden.thing"'))
    end

    after do
      release.set
    end

    it 'logs the error at once' do
      expect(Artery.logger).to have_received(:error).with(/\A\[Backend\] 'Permissions Violation/)
    end
  end

  context 'when two errors follow each other' do
    let(:reported) { [] }

    before do
      allow(Artery).to receive(:handle_error) { |error| reported << error.message }
      client.send(:err_cb_call, client, NATS::IO::ServerError.new("'First'"), nil)
      client.send(:err_cb_call, client, NATS::IO::ServerError.new("'Second'"), nil)
      wait_for_reports
    end

    it 'reports them in order' do
      expect(reported).to eq(["NATS server error: 'First'", "NATS server error: 'Second'"])
    end
  end

  context 'when the backend is stopped and connected again' do
    let(:reported_error) { having_attributes(message: "NATS server error: 'Second'") }

    before do
      client.send(:err_cb_call, client, NATS::IO::ServerError.new("'First'"), nil)
      backend.stop
      backend.connect
      client.send(:err_cb_call, client, NATS::IO::ServerError.new("'Second'"), nil)
      wait_for_reports
    end

    it 'reports the errors that follow' do
      expect(Artery).to have_received(:handle_error).with(reported_error)
    end
  end

  context 'when the error handler uses the database' do
    # A test transaction would share its connection with every thread.
    self.use_transactional_tests = false

    let(:reporting_threads) { [] }
    let(:connection_owners) { ActiveRecord::Base.connection_pool.connections.map(&:owner) }

    before do
      allow(Artery).to receive(:handle_error) do
        ActiveRecord::Base.connection.select_value('select 1')
        reporting_threads << Thread.current
      end
      client.send(:err_cb_call, client, NATS::IO::ServerError.new("'First'"), nil)
      wait_for_reports
    end

    it 'returns the connection to the pool after the report', :aggregate_failures do
      expect(reporting_threads).to be_one
      expect(connection_owners).not_to include(*reporting_threads)
    end
  end

  context 'when the server rejects authentication' do
    before do
      client.send(:process_err, "'Authorization Violation'")
      wait_for_reports
    end

    it 'leaves the error to nats-pure' do
      expect(server).to include(error_received: true)
    end
  end

  context 'when nats-pure reports an authentication error' do
    before do
      client.send(:err_cb_call, client, NATS::IO::AuthError.new("'Authorization Violation'"), nil)
      wait_for_reports
    end

    it 'reports a backend error' do
      expect(Artery).to have_received(:handle_error).with(an_instance_of(Artery::BackendError))
    end
  end

  context 'when nats-pure reports a network error' do
    before do
      client.send(:err_cb_call, client, Errno::ECONNRESET.new, nil)
      wait_for_reports
    end

    it 'leaves it to the disconnect and reconnect events' do
      expect(Artery).not_to have_received(:handle_error)
    end
  end

  context 'when the error handler fails' do
    let(:reported_error) { having_attributes(message: "NATS server error: 'Second'") }

    before do
      allow(Artery).to receive(:handle_error)
        .with(having_attributes(message: "NATS server error: 'First'")).and_raise('error tracker is unavailable')
      allow(Artery.logger).to receive(:error)
      client.send(:err_cb_call, client, NATS::IO::ServerError.new("'First'"), nil)
      client.send(:err_cb_call, client, NATS::IO::ServerError.new("'Second'"), nil)
      wait_for_reports
    end

    it 'logs the failure and reports the next error', :aggregate_failures do
      expect(Artery.logger).to have_received(:error).with(/Failed to report NATS error/)
      expect(Artery).to have_received(:handle_error).with(reported_error)
    end
  end

  context 'when the error handler and the logger fail' do
    let(:logger) { instance_double(Logger, warn: nil, info: nil) }
    let(:reported_error) { having_attributes(message: "NATS server error: 'Second'") }

    before do
      allow(Artery).to receive(:logger).and_return(logger)
      allow(logger).to receive(:error).and_raise(IOError, 'closed stream')
      allow(Warning).to receive(:warn)
      allow(Artery).to receive(:handle_error)
        .with(having_attributes(message: "NATS server error: 'First'")).and_raise('error tracker is unavailable')
      client.send(:process_err, "'First'")
      client.send(:err_cb_call, client, NATS::IO::ServerError.new("'Second'"), nil)
      wait_for_reports
    end

    it 'still reports the next error' do
      expect(Artery).to have_received(:handle_error).with(reported_error)
    end
  end
end
