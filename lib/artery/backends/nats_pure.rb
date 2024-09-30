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
            Artery.logger.debug "Reconnected to server at #{client.connected_server}"
          end

          client.on_disconnect do
            Artery.logger.debug 'Disconnected!'
          end

          client.on_close do
            Artery.logger.debug 'Connection to NATS closed'
          end
          client
        end

        Artery.logger.debug "Connected to #{@client.connected_server}"
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
