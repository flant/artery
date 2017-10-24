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

      def request(route, data, opts = {}, &blk)
        opts[:max] = 1 unless opts.key?(:max) # Set max to 1 for auto-unsubscribe from INBOX-channels
        sid = nil

        do_request = proc do
          sid = ::NATS.request(route, data, opts) do |*resp|
            correct_request_stop(sid) { yield(*resp) }
          end

          requests << sid

          ::NATS.timeout(sid, Artery.request_timeout) do
            correct_request_stop(sid) { yield(TimeoutError.new(request: { route: route, data: data })) }
          end
        end

        if Artery.worker
          do_request.call(&blk)
        elsif EM.reactor_running? && (EM.reactor_thread != Thread.current)
          wait_em_to_stop
        elsif EM.reactor_running?
          do_request.call(&blk)
        else
          start do
            @inside_sync_request = true

            do_request.call(&blk)
          end
          @inside_sync_request = nil
        end
      end
      # rubocop:enable Metrics/AbcSize

      def publish(*args, &blk)
        do_publish = proc do
          rid = SecureRandom.uuid

          requests << rid

          ::NATS.publish(*args) do
            correct_request_stop(rid) {}
          end
        end

        if EM.reactor_running?
          do_publish.call(&blk)
        elsif EM.reactor_running? && (EM.reactor_thread != Thread.current)
          wait_em_to_stop
        elsif EM.reactor_running?
          do_publish.call(&blk)
        else
          start do
            do_publish.call(&blk)
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

      def correct_request_stop(sid = nil)
        yield
      ensure
        requests.delete(sid) if sid
        stop if @inside_sync_request
      end

      def wait_em_to_stop
        Artery.logger.debug 'WAITING_EM_TO_STOP: it was running in another thread'

        stop if ::NATS.client && !::NATS.client.closing? # WTF???
        sleep(0.1) while EM.reactor_running?
      end
    end
  end
end
