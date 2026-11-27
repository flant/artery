# frozen_string_literal: true

require 'concurrent'
require 'nats/client'

module Artery
  module Backends
    class NATSPure < Base
      PERMISSIONS_VIOLATION = /'Permissions Violation/i.freeze
      # nats-server quotes the subject as Go does, escaping quotes and backslashes.
      DENIED_SUBJECT = /Permissions Violation for .*? (?:to|of) ("(?:[^"\\]|\\.)*")/i.freeze
      GO_ESCAPES = { 'a' => "\a", 'b' => "\b", 'f' => "\f", 'n' => "\n", 'r' => "\r", 't' => "\t", 'v' => "\v" }.freeze

      # nats-pure (2.0-2.8) treats every -ERR from a server with authentication as an authentication error:
      # it drops the connection and removes the server from the pool once a reconnect attempt fails,
      # so a single denied publish or subscription can close the client for good. nats-server keeps the
      # connection open after a permissions violation, so only the error callback is called, as nats.go does.
      module PermissionViolationHandling
        private

        def process_err(err)
          return super unless PERMISSIONS_VIOLATION.match?(err.to_s)

          error = ::NATS::IO::ServerError.new(err)
          synchronize { @last_err = error }
          err_cb_call(self, error, nil)
        end
      end

      # Reports server errors in order on its own thread: on the reading thread of nats-pure a slow error handler
      # would hold back the replies to other requests. Reports that do not fit into the queue are counted and the
      # count is logged from the reporting thread, so the reading thread never waits for the log.
      class ErrorReporter
        QUEUE_SIZE = 100
        STOP_TIMEOUT = 5
        EXIT_TIMEOUT = 2

        @reporters = Set.new
        @registry = Mutex.new

        class << self
          # One exit handler shuts down every reporter still running; terminated ones are forgotten.
          def register(reporter)
            @registry.synchronize do
              @exit_handler ||= at_exit { active.each { |running| running.shutdown(EXIT_TIMEOUT) } }
              @reporters.delete_if(&:terminated?)
              @reporters << reporter
            end
          end

          def unregister(reporter)
            @registry.synchronize { @reporters.delete(reporter) }
          end

          def active
            @registry.synchronize { @reporters.to_a }
          end
        end

        # A reporter that follows a stopped one sends its reports after the reports of the stopped one.
        def initialize(after: nil)
          # One thread keeps the order, started on the first report; SingleThreadExecutor would not bound the queue.
          @executor = Concurrent::ThreadPoolExecutor.new(min_threads: 0, max_threads: 1,
                                                         max_queue: QUEUE_SIZE, fallback_policy: :abort)
          @dropped = Concurrent::AtomicFixnum.new
          @stopping = Mutex.new
          @after = after
          self.class.register(self)
        end

        def post(description, &report)
          @executor.post do
            wait_for_previous
            log_dropped
            report.call
          end
        rescue Concurrent::RejectedExecutionError
          # Once the reporter is shut down nothing would log the count, and no reply is waited for any more.
          @stopping.synchronize do
            if @executor.running?
              @dropped.increment
            else
              Artery.logger.error "NATS error not reported, the reporter is shut down: #{description}"
            end
          end
        end

        # Waits until the reports posted so far are done; they keep being sent if it takes longer.
        def drain(timeout = STOP_TIMEOUT)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
          sleep 0.01 until idle? || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
          log_dropped
          return if idle?

          Artery.logger.warn "NATS error reports still pending #{timeout} s after stopping, they keep being sent"
        end

        def idle?
          @executor.completed_task_count == @executor.scheduled_task_count
        end

        # Takes no more reports; the reports already posted are still sent and the thread ends after them.
        def close
          @executor.shutdown
        end

        def terminated?
          @executor.shutdown?
        end

        def wait_for_termination(timeout = nil)
          @executor.wait_for_termination(timeout)
        end

        # Stops reporting, also when the process exits; reports not done by then are lost.
        def shutdown(timeout = 5)
          @executor.shutdown
          done = @executor.wait_for_termination(timeout)
          @stopping.synchronize { log_dropped }
          return self.class.unregister(self) if done

          Artery.logger.error "NATS error reports not done #{timeout} s after shutting down, they are lost"
        end

        private

        # Runs on the reporting thread only.
        def wait_for_previous
          @after&.wait_for_termination
          @after = nil
        end

        def log_dropped
          count = @dropped.value
          count = @dropped.value until count.zero? || @dropped.compare_and_set(count, 0)
          return if count.zero?

          Artery.logger.error "#{count} NATS error report(s) dropped: #{QUEUE_SIZE} reports were already pending"
        end
      end

      def client
        @client || connect
      end

      def error_reporter
        @error_reporter ||= ErrorReporter.new(after: @stopped_reporter)
      end

      delegate :connected?, :connecting?, :subscribe, :flush, to: :client

      def connect
        @client ||= begin
          client = ::NATS.connect(options)
          client.extend(PermissionViolationHandling)

          client.on_error { |_nc, error, _sub| report_error(error) }

          client.on_reconnect do
            Artery::Instrumentation.instrument(
              :connection, state: :reconnected, server: sanitized_server(client.connected_server)
            )
          end

          client.on_disconnect do
            Artery::Instrumentation.instrument(:connection, state: :disconnected)
          end

          client.on_close do
            Artery::Instrumentation.instrument(:connection, state: :closed)
          end
          client
        end

        Artery::Instrumentation.instrument(
          :connection, state: :connected, server: sanitized_server(@client.connected_server)
        )
        @client.connect unless @client.connected?

        @client
      end

      def stop
        client.close
        stop_error_reporter
        @stop = true
      end

      def start
        @stop = false
        connect

        yield

        sleep 0.1 until @stop
      end

      def request(route, data, opts = {})
        opts[:timeout] ||= Artery.request_timeout
        # Always synchronous for now
        response = client.request route, data, **opts
        yield response.data
      rescue ::NATS::Timeout
        yield(TimeoutError.new(request: { route: route, data: data }))
      rescue ::NATS::IO::NoRespondersError
        yield(NoRespondersError.new("No responders for #{route}", request: { route: route, data: data }))
      end

      def publish(route, data)
        client.publish route, data
      end

      private

      # Frees the reporting thread: at once when the posted reports are sent, otherwise after them. A reporter still
      # sending them is kept for the next one to follow, so the reports keep their order.
      def stop_error_reporter
        return unless @error_reporter

        @error_reporter.drain
        if @error_reporter.idle?
          @error_reporter.shutdown
          @stopped_reporter = nil if @stopped_reporter&.terminated?
        else
          @error_reporter.close
          @stopped_reporter = @error_reporter
        end
        @error_reporter = nil
      end

      # Reports errors sent by the server. Network errors are left to the disconnect and reconnect events.
      def report_error(error)
        return unless error.is_a?(::NATS::IO::ServerError) || error.is_a?(::NATS::IO::AuthError)

        # nats-pure passes these errors unraised, and error handlers need a backtrace.
        error.set_backtrace(caller) unless error.backtrace
        # nats-pure reads the error as bytes; nats-server sends UTF-8.
        message = error.message.to_s.dup.force_encoding(Encoding::UTF_8).scrub
        subject = denied_subject(message)
        error_class = PERMISSIONS_VIOLATION.match?(message) ? PermissionError : BackendError

        error_reporter.post(message) do
          isolate_reporting(error) do
            Artery::Instrumentation.instrument(:connection, state: :error, error: message, subject: subject)
          end
          isolate_reporting(error) do
            Artery.handle_error error_class.new("NATS server error: #{message}",
                                                original_exception: error, subject: subject)
          end
        end
      end

      # Unquotes the subject as Go's strconv.Quote quotes it, keeping printable UTF-8.
      def denied_subject(message)
        quoted = message[DENIED_SUBJECT, 1]
        quoted && quoted[1..-2].gsub(/\\(x\h{2}|u\h{4}|U\h{8}|.)/) do
          code = Regexp.last_match(1)
          code.length > 1 ? [code[1..].hex].pack('U') : GO_ESCAPES.fetch(code, code)
        end
      end

      # Keeps a failing reporting step from skipping the others.
      def isolate_reporting(error)
        yield
      rescue StandardError => e
        Artery.logger.error "Failed to report NATS error #{error.inspect}: #{e.inspect}"
      end

      # Returns server address without credentials, so they never reach instrumentation subscribers (logs).
      def sanitized_server(server)
        return server if server.nil?

        uri = server.is_a?(URI::Generic) ? server.dup : URI.parse(server.to_s)
        uri.password = nil
        uri.user = nil
        uri
      rescue URI::InvalidURIError
        nil
      end

      def options
        options = {}

        options[:servers] = config[:servers]  unless config[:servers].blank?
        options[:user]    = config[:user]     unless config[:user].blank?
        options[:pass]    = config[:password] unless config[:password].blank?

        options[:reconnect_time_wait]    = config[:reconnect_timeout]  unless config[:reconnect_timeout].blank?
        options[:max_reconnect_attempts] = config[:reconnect_attempts] unless config[:reconnect_attempts].blank?
        options[:custom_inbox_prefix]    = inbox_prefix if inbox_prefix

        if ENV.key?('NATS_URL')
          options[:servers] ||= []
          options[:servers] << ENV['NATS_URL']
        end

        options
      end
    end
  end
end
