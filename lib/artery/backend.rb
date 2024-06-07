# frozen_string_literal: true

module Artery
  module Backend
    extend ActiveSupport::Concern

    included do
      class << self
        attr_reader :backend_in_use, :backends

        def register_backend(type, class_name)
          @backends ||= {}
          @backends[type.to_sym] = class_name
        end

        def use_backend(type)
          type = type.to_sym
          raise ArgumentError, "Artery has no registered backend '#{type}'" unless backends.key?(type)

          @backend_in_use = type

          @backend&.stop
          @backend = nil
        end

        def backend
          @backend ||= begin
            backend_class = Artery::Backends.const_get(backends[backend_in_use])
            backend_class.new backend_config
          rescue LoadError, NameError => e
            raise "Unable to load backend #{type}: #{e.message}"
          end
        end

        delegate :start, :stop, :connect, :unsubscribe, to: :backend
      end
    end

    module ClassMethods
      def subscribe(route, options = {})
        backend.subscribe(route, options) do |json, reply, from|
          json = '{}' if json.blank?

          yield(JSON.parse(json).with_indifferent_access, reply, from)
        rescue JSON::ParserError => e
          Artery.handle_error FormatError.new(Routing.uri(from), json, original_exception: e,
                                                                       subscription: { route: from, data: json })
        end
      end

      # rubocop:disable Metrics/AbcSize
      def request(route, data = nil, options = {})
        raise ArgumentError, 'You must provide block to handle response' unless block_given?

        handler = Multiblock.wrapper
        uri = Routing.uri(route)

        yield(handler)

        data ||= {}
        Artery.logger.debug "REQUESTED: <#{uri.to_route}> #{data.to_json}"

        backend.request(uri.to_route, data.to_json, options) do |message|
          if message.is_a?(Error) # timeout case
            Artery.logger.debug "REQUEST ERROR: <#{uri.to_route}> #{message.message}"
            handler.call :error, message
          else
            Artery.logger.debug "REQUEST RESPONSE: <#{uri.to_route}> #{message}"
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
        backend.publish(route, data.to_json)
        Artery.logger.debug "PUBLISHED: <#{route}> #{data.to_json}"
      end
    end
  end
end
