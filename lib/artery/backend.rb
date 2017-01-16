module Artery
  module Backend
    def backend
      @@backend ||= Backends::NATS.new backend_config
    end

    delegate :start, :stop, :connect, :unsubscribe, to: :backend

    def subscribe(route, options = {}, &blk)
      backend.subscribe(route, options) do |message, reply, from|
        blk.call(JSON.parse(message), reply, from)
      end
    end

    def request(route, data = nil, options = {}, &blk)
      raise ArgumentError, 'You must provide block to handle response' unless block_given?

      backend.request(route, data.to_json) do |message|
        puts "RESPONSE RECEIVED: #{message}"
        response = JSON.parse(message)
        blk.call(response)
      end
    end

    def publish(route, data)
      backend.publish(route, data.to_json) do
        puts "PUBLISHED!"
      end
    end
  end
end
