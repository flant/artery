module Artery
  module Model
    autoload :Subscriptions, 'artery/model/subscriptions'
    autoload :Callbacks,     'artery/model/callbacks'

    def artery_model(options = {})
      extend ClassMethods
      include InstanceMethods

      options[:name] ||= self.to_s.demodulize.underscore.to_sym
      options[:source] = false if options[:source].nil?
      options[:uuid_attribute] = :uuid if options[:uuid_attribute].nil?

      class_attribute :artery, instance_writer: false

      self.artery = options.merge({
        representations: {
          _default: proc { attributes }
        }
      })

      Artery.register_model self

      include Subscriptions
      include Callbacks if artery_source_model?
    end

    module ClassMethods
      # Always clone artery configuration in subclass from parent class
      def inherited(subClass)
        self._artery = self._artery.clone
      end

      def artery_model_name
        artery[:name]
      end

      def artery_source_model?
        artery[:source]
      end

      def artery_uuid_attribute
        artery[:uuid_attribute]
      end

      def artery_representation(*services, &blk)
        services.each do |service_name|
          self.artery[:representations][service_name.to_sym] = blk
        end
      end

      def artery_default_representation(&blk)
        artery_representation :_default, &blk
      end

      def artery_version(version = nil)
        if version
          self.artery[:version] = version
        else
          self.artery[:version] || 'v1'
        end
      end
    end

    module InstanceMethods
      def artery_uuid
        send(artery[:uuid_attribute] || :uuid)
      end

      def to_artery(service_name = nil)
        if service_name && artery[:representations].key?(service_name.to_sym)
          instance_eval(&artery[:representations][service_name.to_sym])
        else
          instance_eval(&artery[:representations][:_default])
        end
      end
    end
  end
end
