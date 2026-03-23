# frozen_string_literal: true

require 'nats/client'

module Artery
  module Backends
    class NATSPure < Base
      def client
        @client || connect
      end

      delegate :connected?, :connecting?, :subscribe, to: :client

      def connect
        @client ||= begin
          client = ::NATS.connect(options)

          client.on_reconnect do
            Artery::Instrumentation.instrument(:connection, state: :reconnected, server: client.connected_server)
          end

          client.on_disconnect do
            Artery::Instrumentation.instrument(:connection, state: :disconnected)
          end

          client.on_close do
            Artery::Instrumentation.instrument(:connection, state: :closed)
          end
          client
        end

        Artery::Instrumentation.instrument(:connection, state: :connected, server: @client.connected_server)
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
      end

      def publish(route, data)
        client.publish route, data
      end

      private

      def options
        options = {}

        options[:servers] = config[:servers]  unless config[:servers].blank?
        options[:user]    = config[:user]     unless config[:user].blank?
        options[:pass]    = config[:password] unless config[:password].blank?

        options[:reconnect_time_wait]    = config[:reconnect_timeout]  unless config[:reconnect_timeout].blank?
        options[:max_reconnect_attempts] = config[:reconnect_attempts] unless config[:reconnect_attempts].blank?

        if ENV.key?('NATS_URL')
          options[:servers] ||= []
          options[:servers] << ENV['NATS_URL']
        end

        options
      end
    end
  end
end
