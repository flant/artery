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
        EXIT_TIMEOUT = 2

        def initialize
          # One thread keeps the order; SingleThreadExecutor would not bound the queue.
          @executor = Concurrent::ThreadPoolExecutor.new(min_threads: 1, max_threads: 1, max_queue: QUEUE_SIZE,
                                                         fallback_policy: :abort)
          @dropped = Concurrent::AtomicFixnum.new
          at_exit { shutdown(EXIT_TIMEOUT) }
        end

        def post(&report)
          @executor.post do
            log_dropped
            report.call
          end
        rescue Concurrent::RejectedExecutionError
          @dropped.increment
        end

        # Waits until the reports posted so far are done.
        def drain(timeout = 5)
          done = Concurrent::Event.new
          post { done.set }
          done.wait(timeout)
        end

        # Waits for the pending reports, and logs those that are dropped or not done in time.
        def shutdown(timeout = 5)
          @executor.shutdown
          done = @executor.wait_for_termination(timeout)
          log_dropped
          Artery.logger.error "NATS error reports not done #{timeout} s after stopping, they are lost" unless done
        end

        private

        def log_dropped
          count = @dropped.value
          return unless count.positive?

          @dropped.decrement(count)
          Artery.logger.error "#{count} NATS error report(s) dropped: #{QUEUE_SIZE} reports were already pending"
        end
      end

      def client
        @client || connect
      end

      def error_reporter
        @error_reporter ||= ErrorReporter.new
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
        @error_reporter&.shutdown
        @error_reporter = nil
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

      # Reports errors sent by the server. Network errors are left to the disconnect and reconnect events.
      def report_error(error)
        return unless error.is_a?(::NATS::IO::ServerError) || error.is_a?(::NATS::IO::AuthError)

        # nats-pure passes these errors unraised, and error handlers need a backtrace.
        error.set_backtrace(caller) unless error.backtrace
        # nats-pure reads the error as bytes; nats-server sends UTF-8.
        message = error.message.to_s.dup.force_encoding(Encoding::UTF_8).scrub
        subject = denied_subject(message)
        error_class = PERMISSIONS_VIOLATION.match?(message) ? PermissionError : BackendError

        error_reporter.post do
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
