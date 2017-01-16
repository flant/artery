module Artery
  module Backend
    extend ActiveSupport::Concern

    included do
      class << self
        attr_accessor :backend

        def backend
          @backend ||= Backends::NATS.new backend_config
        end

        delegate :start, :stop, :connect, :unsubscribe, to: :backend
      end
    end

    module ClassMethods
      def subscribe(route, options = {})
        backend.subscribe(route, options) do |message, reply, from|
          yield(JSON.parse(message), reply, from)
        end
      end

      def request(route, data = nil, _options = {})
        raise ArgumentError, 'You must provide block to handle response' unless block_given?

        backend.request(route, data.to_json) do |message|
          puts "RESPONSE RECEIVED: #{message}"
          response = JSON.parse(message)
          yield(response)
        end
      end

      def publish(route, data)
        backend.publish(route, data.to_json) do
          puts 'PUBLISHED!'
        end
      end
    end
  end
end
