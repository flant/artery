# frozen_string_literal: true
require 'nats/client'

module Artery
  module Backends
    class NATS < Base
      def start(&blk)
        ::NATS.start(options, &blk)
      end

      def connect(&blk)
        ::NATS.connect(options, &blk)
      end

      def subscribe(*args, &blk)
        ::NATS.subscribe(*args, &blk)
      end

      def unsubscribe(*args, &blk)
        ::NATS.unsubscribe(*args, &blk)
      end

      def request(*args)
        if EM.reactor_running?
          sid = ::NATS.request(*args) do |*resp|
            yield(*resp)

            requests.delete(sid)
            stop if @inside_sync_request
          end

          requests << sid

          ::NATS.timeout(sid, Artery.request_timeout) do
            yield(TimeoutError.new)

            requests.delete(sid)
            stop if @inside_sync_request
          end
        else
          start do
            @inside_sync_request = true

            sid = ::NATS.request(*args) do |*resp|
              yield(*resp)

              requests.delete(sid)
              stop
            end

            requests << sid

            ::NATS.timeout(sid, Artery.request_timeout) do
              yield(TimeoutError.new)

              requests.delete(sid)
              stop
            end
          end
        end
      end

      def publish(*args, &blk)
        if EM.reactor_running?
          ::NATS.publish(*args, &blk)
        else
          start do
            ::NATS.publish(*args) do |*resp|
              yield(*resp) if block_given?
              stop
            end
          end
        end
      end

      def stop(*args, &blk)
        return false unless requests.blank?

        ::NATS.stop(*args, &blk)
        true
      end

      private

      def requests
        @requests ||= []
      end

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
    end
  end
end
