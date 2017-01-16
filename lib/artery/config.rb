module Artery
  module Config
    mattr_accessor :message_class, :service_name, :version

    def configure(&blk)
      blk.call(self)
    end

    # Ability to redefine message class (for example, for non-activerecord applications)
    def message_class
      @@message_class || Message
    end

    def service_name
      @@service_name || raise(RuntimeError, 'Artery service_name must be configured!')
    end

    def backend_config
      @@backend_config ||= {
        servers:            ENV.fetch('ARTERY_SERVERS')            { '' }.split(','),
        user:               ENV.fetch('ARTERY_USER')               { nil },
        password:           ENV.fetch('ARTERY_PASSWORD')           { nil },
        reconnect_timeout:  ENV.fetch('ARTERY_RECONNECT_TIMEOUT')  { 1 },
        reconnect_attempts: ENV.fetch('ARTERY_RECONNECT_ATTEMPTS') { 10 }
      }
    end
  end
end
