module Artery
  module Config
    extend ActiveSupport::Concern

    included do
      class << self
        attr_accessor :message_class, :last_model_update_class, :service_name, :backend_config, :request_timeout

        # Ability to redefine message class (for example, for non-activerecord applications)
        def message_class
          @message_class || Artery::Message
        end

        def last_model_update_class
          @last_model_update_class || Artery::LastModelUpdate
        end

        def service_name
          @service_name || raise('Artery service_name must be configured!')
        end

        def request_timeout
          @request_timeout || ENV.fetch('ARTERY_REQUEST_TIMEOUT') { 10 }
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

    module ClassMethods
      def configure
        yield(self)
      end
    end
  end
end
