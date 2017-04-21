module Artery
  module Model
    autoload :Subscriptions,  'artery/model/subscriptions'
    autoload :Callbacks,      'artery/model/callbacks'

    def artery_model(options = {})
      extend ClassMethods
      include InstanceMethods

      options[:name] ||= to_s.demodulize.underscore.to_sym
      options[:source] = false if options[:source].nil?
      options[:uuid_attribute] = :uuid if options[:uuid_attribute].nil?

      class_attribute :artery, instance_writer: false

      self.artery = options.merge(representations: {
                                    _default: proc { attributes }
                                  })

      include Subscriptions
      include Callbacks if artery_source_model?

      artery_scope :all, -> { all }
    end

    module ClassMethods
      # Always clone artery configuration in subclass from parent class
      def inherited(_subClass)
        self.artery = artery.clone
        super
      end

      def artery_model_name
        artery[:name]
      end

      def artery_model_name_plural
        artery_model_name.to_s.pluralize.to_sym
      end

      def artery_source_model?
        artery[:source]
      end

      def artery_uuid_attribute
        artery[:uuid_attribute]
      end

      def artery_representation(*services, &blk)
        services.each do |service_name|
          artery[:representations][service_name.to_sym] = blk
        end
      end

      def artery_default_representation(&blk)
        artery_representation :_default, &blk
      end

      def artery_version(version = nil)
        if version
          artery[:version] = version
        else
          artery[:version] || 'v1'
        end
      end

      def artery_scope(name, lmbd)
        scope :"artery_#{name}", lmbd
      end
    end

    module InstanceMethods
      def artery_notify_message(action, extra_data = {})
        Artery.message_class.create! model: self.class.artery_model_name,
                                     action: action,
                                     #  version: self.class.artery_version, TODO:
                                     data: { uuid: artery_uuid, updated_by_service: artery_updated_by_service }.merge(extra_data)
      end

      def artery_uuid
        send(self.class.artery_uuid_attribute)
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
