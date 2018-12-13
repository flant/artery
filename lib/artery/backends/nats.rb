# frozen_string_literal: true

require 'nats/client'

module Artery
  module Backends
    class NATS < Base
      def initialize(*args)
        super
        @root_fiber = Fiber.current
      end

      def start(&blk)
        ::NATS.start(options, &blk)
      end

      def connect(&blk)
        return if connected?

        ::NATS.connect(options, &blk)
      end

      def connected?
        ::NATS.connected?
      end

      def subscribe(*args, &blk)
        connect

        ::NATS.subscribe(*args) do |*msg|
          Fiber.new do
            # requests inside subscription block will be synchronous
            blk.call(*msg)
          end.resume
        end
      end

      def unsubscribe(*args, &blk)
        connect

        ::NATS.unsubscribe(*args, &blk)
      end

      def request(route, data, opts = {}, &blk)
        connect

        opts[:max] = 1 unless opts.key?(:max) # Set max to 1 for auto-unsubscribe from INBOX-channels
        opts[:timeout] ||= Artery.request_timeout

        if @root_fiber && Fiber.current != @root_fiber
          Rails.logger.debug 'SYNC REQUEST'
          response = ::NATS.request(route, data, opts)
          response ||= TimeoutError.new(request: { route: route, data: data })

          yield(*response)
        else
          Rails.logger.debug 'ASYNC REQUEST'
          sid = ::NATS.request(route, data, opts.except(:timeout)) do |*resp|
            yield(*resp)
          end

          ::NATS.timeout(sid, opts[:timeout]) do
            yield(TimeoutError.new(request: { route: route, data: data }))
          end
        end
      end

      def publish(*args, &blk)
        connect

        ::NATS.publish(*args)
      end

      def stop(*args, &blk)
        ::NATS.stop(*args, &blk)
        true
      end

      private

      # rubocop:disable Metrics/AbcSize
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
      # rubocop:enable Metrics/AbcSize
    end
  end
end
