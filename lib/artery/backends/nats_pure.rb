# frozen_string_literal: true

require 'nats/client'

module Artery
  module Backends
    class NATSPure < Base
      PERMISSIONS_VIOLATION = /'Permissions Violation/i.freeze
      DENIED_SUBJECT = /Permissions Violation for .*? (?:to|of) "([^"]*)"/i.freeze

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

      def client
        @client || connect
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
        message = error.message.to_s
        subject = message[DENIED_SUBJECT, 1]
        error_class = PERMISSIONS_VIOLATION.match?(message) ? PermissionError : BackendError

        isolate_reporting(error) do
          Artery::Instrumentation.instrument(:connection, state: :error, error: message, subject: subject)
        end
        isolate_reporting(error) do
          Artery.handle_error error_class.new("NATS server error: #{message}",
                                              original_exception: error, subject: subject)
        end
      end

      # Runs in the reading thread of nats-pure: an exception here would make it reconnect.
      def isolate_reporting(error)
        yield
      rescue StandardError => e
        Artery.logger.error "Failed to report NATS error #{error.inspect}: #{e.inspect}"
      end

      # Restricted NATS users may subscribe only to inboxes of their own service.
      def inbox_prefix
        config[:inbox_prefix].presence || ENV['ARTERY_INBOX_PREFIX'].presence ||
          ("_INBOX.#{Artery.service_name}" if Artery.service_name?)
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
