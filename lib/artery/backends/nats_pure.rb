# frozen_string_literal: true

require 'nats/io/client'

module Artery
  module Backends
    class NATSPure < Base
      attr_accessor :client

      def initialize(*args)
        super
        connect
      end

      def client
        @client ||= ::NATS::IO::Client.new
      end

      delegate :connected?, :connecting?, to: :client

      def connect
        client.connect(options)
        Artery.logger.debug "Connected to #{client.connected_server}"
      end

      def stop
        client.close
      end

      # subscribe, unsubscribe, start not implemented, should use this backend ONLY for synchronous requests

      def request(route, data, opts = {}, &blk)
        # Always synchronous for now
        response = client.request route, data, timeout: Artery.request_timeout
        yield response.data
      rescue ::NATS::IO::Timeout
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
