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
          begin
            message ||= '{}'
            yield(JSON.parse(message).with_indifferent_access, reply, from)
          rescue JSON::ParserError
            Rails.logger.error "Received message from #{from} in wrong format: #{message}"
          end
        end
      end

      def request(route, data = nil, options = {}, &blk)
        raise ArgumentError, 'You must provide block to handle response' unless block_given?
        handler = Multiblock.wrapper

        # FIXME: Temporary for backward compatibility
        if options[:multihandler] == true
          yield(handler)
        else
          handler.success(&blk)
        end

        backend.request(route, data.to_json) do |message|
          if message.is_a?(Error) # timeout case
            handler.call :error, message
          else
            Rails.logger.info "RESPONSE RECEIVED: #{message}"
            begin
              message ||= '{}'
              response = JSON.parse(message).with_indifferent_access

              if response.key?(:error)
                handler.call :error, RequestError.new(Routing.uri(route), response)
              else
                handler.call :success, response
              end
            rescue JSON::ParserError
              Rails.logger.error "Received message from #{route} in wrong format: #{message}"
            end
          end
        end
      end

      def publish(route, data)
        backend.publish(route, data.to_json) do
          Rails.logger.info 'PUBLISHED!'
        end
      end
    end
  end
end
