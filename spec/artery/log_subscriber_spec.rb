# frozen_string_literal: true

describe Artery::LogSubscriber do
  let(:log_output) { StringIO.new }
  let(:test_logger) { ActiveSupport::TaggedLogging.new(Logger.new(log_output)) }

  around do |example|
    saved = %i[@logger @log_messages @message_body_max_size].to_h do |name|
      [name, { defined: Artery.instance_variable_defined?(name), value: Artery.instance_variable_get(name) }]
    end

    Artery.instance_variable_set(:@logger, test_logger)
    Artery.logger.push_tags 'Artery'

    example.run
  ensure
    saved.each do |name, state|
      if state[:defined]
        Artery.instance_variable_set(name, state[:value])
      elsif Artery.instance_variable_defined?(name)
        Artery.remove_instance_variable(name)
      end
    end
  end

  def log_contents
    log_output.string
  end

  describe 'request event' do
    it 'logs [REQ] for stage :sent' do
      Artery::Instrumentation.instrument(:request, stage: :sent, route: 'svc.model.get', data: { uuid: '123' })

      expect(log_contents).to include('[REQ]')
      expect(log_contents).to include('svc.model.get')
      expect(log_contents).to include('123')
    end

    it 'logs [RESP] with duration for stage :response' do
      Artery::Instrumentation.instrument(:request, stage: :response, route: 'svc.model.get',
                                                   data: { ok: true }, duration_ms: 12.345)

      expect(log_contents).to include('[RESP]')
      expect(log_contents).to include('svc.model.get')
      expect(log_contents).to include('12.3ms')
    end

    it 'logs [REQ ERR] with duration for stage :error (always, even when log_messages is off)' do
      Artery.log_messages = false
      Artery::Instrumentation.instrument(:request, stage: :error, route: 'svc.model.get',
                                                   error: 'timeout', duration_ms: 15_000.0)

      expect(log_contents).to include('[REQ ERR]')
      expect(log_contents).to include('timeout')
      expect(log_contents).to include('15000.0ms')
    end
  end

  describe 'publish event' do
    it 'logs [PUB]' do
      Artery::Instrumentation.instrument(:publish, route: 'svc.model.create', data: { action: 'create' })

      expect(log_contents).to include('[PUB]')
      expect(log_contents).to include('svc.model.create')
    end
  end

  describe 'message event' do
    it 'logs [RECV] for stage :received' do
      Artery::Instrumentation.instrument(:message, stage: :received, route: 'svc.model.update',
                                                   data: { uuid: 'abc' })

      expect(log_contents).to include('[RECV]')
      expect(log_contents).to include('svc.model.update')
    end

    it 'logs [SKIP] for stage :skipped' do
      Artery::Instrumentation.instrument(:message, stage: :skipped, reason: 'sync in progress')

      expect(log_contents).to include('[SKIP]')
      expect(log_contents).to include('sync in progress')
    end

    it 'logs [DONE] with duration for stage :handled' do
      Artery::Instrumentation.instrument(:message, stage: :handled, route: 'svc.model.create') { sleep 0.01 }

      expect(log_contents).to include('[DONE]')
      expect(log_contents).to match(/\d+\.\d+ms/)
    end
  end

  describe 'when log_messages? is false' do
    before { Artery.log_messages = false }

    it 'suppresses request and publish events' do
      Artery::Instrumentation.instrument(:request, stage: :sent, route: 'svc.model.get', data: { uuid: '1' })
      Artery::Instrumentation.instrument(:publish, route: 'svc.model.create', data: {})

      expect(log_contents).not_to include('[REQ]')
      expect(log_contents).not_to include('[PUB]')
    end

    it 'suppresses message events' do
      Artery::Instrumentation.instrument(:message, stage: :received, route: 'svc.model.update', data: {})
      Artery::Instrumentation.instrument(:message, stage: :skipped, reason: 'test')

      expect(log_contents).not_to include('[RECV]')
      expect(log_contents).not_to include('[SKIP]')
    end

    it 'still logs lifecycle events' do
      Artery::Instrumentation.instrument(:connection, state: :connected, server: 'nats://localhost:4222')
      Artery::Instrumentation.instrument(:worker, action: :started, worker_id: 'abc123')

      expect(log_contents).to include('[Backend] connected')
      expect(log_contents).to include('started')
    end
  end

  describe 'body truncation' do
    it 'truncates bodies exceeding message_body_max_size' do
      Artery.message_body_max_size = 32
      large_data = { payload: 'x' * 100 }

      Artery::Instrumentation.instrument(:request, stage: :sent, route: 'svc.model.get', data: large_data)

      expect(log_contents).to include('truncated')
      expect(log_contents).to include('bytes total')
    end

    it 'does not truncate when message_body_max_size is nil' do
      Artery.message_body_max_size = nil
      large_data = { payload: 'x' * 2000 }

      Artery::Instrumentation.instrument(:request, stage: :sent, route: 'svc.model.get', data: large_data)

      expect(log_contents).not_to include('truncated')
      expect(log_contents).to include('x' * 100)
    end
  end

  describe 'connection event' do
    it 'logs connected' do
      Artery::Instrumentation.instrument(:connection, state: :connected, server: 'nats://10.0.0.1:4222')

      expect(log_contents).to include('[Backend] connected to nats://10.0.0.1:4222')
    end

    it 'logs disconnected' do
      Artery::Instrumentation.instrument(:connection, state: :disconnected)

      expect(log_contents).to include('[Backend] disconnected')
    end
  end

  describe 'worker event' do
    it 'logs started' do
      Artery::Instrumentation.instrument(:worker, action: :started, worker_id: 'w42')

      expect(log_contents).to include('started (id=w42)')
    end

    it 'logs subscribing' do
      Artery::Instrumentation.instrument(:worker, action: :subscribing, route: 'svc.model.get')

      expect(log_contents).to include('[SUB] <svc.model.get>')
    end
  end

  describe 'sync event' do
    it 'logs receive_all with duration' do
      Artery::Instrumentation.instrument(:sync, stage: :receive_all, route: 'svc.models.get_all') { sleep 0.01 }

      expect(log_contents).to include('[SYNC] receive_all')
      expect(log_contents).to include('svc.models.get_all')
    end
  end

  describe 'lock event' do
    it 'logs waiting and acquired with duration' do
      Artery::Instrumentation.instrument(:lock, state: :waiting, latest_index: 42)
      Artery::Instrumentation.instrument(:lock, state: :acquired, latest_index: 42) { sleep 0.01 }

      expect(log_contents).to include('[LOCK] waiting (latest_index: 42)')
      expect(log_contents).to include('[LOCK] acquired (latest_index: 42,')
      expect(log_contents).to match(/acquired.*\d+\.\d+ms/)
    end
  end
end
