# frozen_string_literal: true
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
            message = '{}' if message.blank?

            yield(JSON.parse(message).with_indifferent_access, reply, from)
          rescue JSON::ParserError => e
            Artery.handle_error FormatError.new(Routing.uri(from), message, original_exception: e,
                                                                            subscription: { route: from, data: message })
          end
        end
      end

      # rubocop:disable Metrics/AbcSize
      def request(route, data = nil, _options = {})
        raise ArgumentError, 'You must provide block to handle response' unless block_given?
        handler = Multiblock.wrapper
        uri = Routing.uri(route)

        yield(handler)

        data ||= {}
        Artery.logger.debug "REQUESTED: [#{uri.to_route}] #{data.to_json}"

        backend.request(uri.to_route, data.to_json) do |message|
          if message.is_a?(Error) # timeout case
            Artery.logger.debug "REQUEST ERROR: [#{uri.to_route}] #{message.message}"
            handler.call :error, message
          else
            Artery.logger.debug "REQUEST RESPONSE: [#{uri.to_route}] #{message}"
            begin
              message ||= '{}'
              response = JSON.parse(message).with_indifferent_access

              if response.key?(:error)
                handler.call :error, RequestError.new(uri, response, request: { route: uri.to_route, data: data.to_json },
                                                                     response: message)
              else
                handler.call :success, response
              end
            rescue JSON::ParserError => e
              Artery.handle_error FormatError.new(uri, message, original_exception: e,
                                                                request: { route: uri.to_route, data: data.to_json },
                                                                response: message)
            end
          end
        end
      end
      # rubocop:enable Metrics/AbcSize

      def publish(route, data)
        backend.publish(route, data.to_json) do
          Artery.logger.debug "PUBLISHED: [#{route}] #{data.to_json}"
        end
      end
    end
  end
end
