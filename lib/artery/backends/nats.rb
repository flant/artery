require 'nats/client'

module Artery
  module Backends
    class NATS < Base
      REQUEST_TIMEOUT = 5.seconds

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

      def request(*args, &blk)
        if EM.reactor_running?
          ::NATS.request(*args, &blk)
        else
          start do
            ::NATS.request(*args) do |*resp|
              blk.call(*resp) if block_given?
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
              blk.call(*resp) if block_given?
              stop
            end
          end
        end
      end

      def stop(*args, &blk)
        ::NATS.stop(*args, &blk)
      end

      private

      def options
        options = {}

        options[:servers] = config[:servers]  unless config[:servers].blank?
        options[:user]    = config[:user]     unless config[:user].blank?
        options[:pass]    = config[:password] unless config[:password].blank?

        options[:reconnect_time_wait]    = config[:reconnect_timeout]  unless config[:reconnect_timeout].blank?
        options[:max_reconnect_attempts] = config[:reconnect_attempts] unless config[:reconnect_attempts].blank?

        options
      end
    end
  end
end
