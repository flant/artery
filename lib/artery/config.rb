# frozen_string_literal: true

module Artery
  module Config
    extend ActiveSupport::Concern

    included do # rubocop:disable Metrics/BlockLength
      class << self
        attr_accessor :message_class, :subscription_info_class, :service_name, :backend_config, :request_timeout,
                      :error_handler

        # Ability to redefine message class (for example, for non-activerecord applications)
        def message_class
          @message_class || get_model_class(:Message)
        end

        def subscription_info_class
          @subscription_info_class || get_model_class(:SubscriptionInfo)
        end

        def service_name
          @service_name || raise('Artery service_name must be configured!')
        end

        def logger
          @logger || (self.logger = defined?(Rails) ? Rails.logger : Logger.new($stdout))
        end

        def logger=(logger)
          @logger = ActiveSupport::TaggedLogging.new(logger)
          @logger.push_tags 'Artery'
          @logger
        end

        def request_timeout
          @request_timeout || ENV.fetch('ARTERY_REQUEST_TIMEOUT', '15').to_i
        end

        def error_handler
          @error_handler || (defined?(Artery::RavenErrorHandler) ? Artery::RavenErrorHandler : Artery::ErrorHandler)
        end

        def backend_config
          @backend_config ||= {
            servers: ENV.fetch('ARTERY_SERVERS', '').split(','),
            user: ENV.fetch('ARTERY_USER', nil),
            password: ENV.fetch('ARTERY_PASSWORD', nil),
            reconnect_timeout: ENV.fetch('ARTERY_RECONNECT_TIMEOUT', '1').to_i,
            reconnect_attempts: ENV.fetch('ARTERY_RECONNECT_ATTEMPTS', '10').to_i
          }
        end

        private

        def get_model_class(model)
          if defined?(::ActiveRecord)
            ::Artery::ActiveRecord.const_get(model, false)
          elsif defined?(::NoBrainer)
            ::Artery::NoBrainer.const_get(model, false)
          else
            raise ArgumentError, 'No supported ORMs found'
          end
        end
      end
    end

    module ClassMethods
      def configure
        yield(self)
      end
    end
  end
end
