module Artery
  module Config
    extend ActiveSupport::Concern

    # rubocop:disable Metrics/BlockLength
    included do
      class << self
        attr_accessor :message_class, :subscription_info_class, :service_name, :backend_config, :request_timeout,
                      :error_handler, :logger

        # Ability to redefine message class (for example, for non-activerecord applications)
        def message_class
          @message_class || Artery::Message
        end

        def subscription_info_class
          @subscription_info_class || Artery::SubscriptionInfo
        end

        def service_name
          @service_name || raise('Artery service_name must be configured!')
        end

        def logger
          @logger ||= if defined?(Rails)
                        Rails.logger
                      else
                        Logger.new(STDOUT)
                      end
        end

        def request_timeout
          @request_timeout || ENV.fetch('ARTERY_REQUEST_TIMEOUT') { 30 }
        end

        def error_handler
          @error_handler || (defined?(Artery::RavenErrorHandler) ? Artery::RavenErrorHandler : Artery::ErrorHandler)
        end

        def backend_config
          @backend_config ||= {
            servers:            ENV.fetch('ARTERY_SERVERS')            { '' }.split(','),
            user:               ENV.fetch('ARTERY_USER')               { nil },
            password:           ENV.fetch('ARTERY_PASSWORD')           { nil },
            reconnect_timeout:  ENV.fetch('ARTERY_RECONNECT_TIMEOUT')  { 1 },
            reconnect_attempts: ENV.fetch('ARTERY_RECONNECT_ATTEMPTS') { 10 }
          }
        end
      end
    end
    # rubocop:enable Metrics/BlockLength

    module ClassMethods
      def configure
        yield(self)
      end
    end
  end
end
