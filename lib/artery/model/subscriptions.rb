module Artery
  module Model
    module Subscriptions
      extend ActiveSupport::Concern

      included do
        artery_add_get_subscriptions if artery_source_model?
      end

      module ClassMethods
        def artery_find!(uuid)
          find_by! "#{artery_uuid_attribute}": uuid
        end

        def artery_add_subscription(route, handler = nil, &blk)
          artery[:subscriptions] ||= {}
          if handler
            handler = { handler: handler } # KOSTYL: Multiblock::Wrapper is BasicObject, no way to identify it
          end
          artery[:subscriptions][route] = handler || blk
        end

        def artery_watch_model(service: nil, model: nil, action: nil)
          model ||= artery_model_name
          handler = Multiblock.wrapper
          yield(handler)

          artery_add_subscription Artery::Routing.compile(service: service, model: model, action: '*'), handler
        end

        def artery_add_get_subscriptions
          artery_add_subscription Artery::Routing.compile(model: artery_model_name, action: :get) do |data, reply, sub|
            puts "HEY-HEY-HEY, message on GET with arguments: `#{[data, reply, sub].inspect}`!"

            obj = artery_find! data['uuid']
            service = data['service']

            Artery.publish(reply, obj.to_artery(service))
          end

          artery_add_subscription Artery::Routing.compile(model: artery_model_name, action: :get_all) do |data, reply, sub|
            puts "HEY-HEY-HEY, message on GET_ALL with arguments: `#{[data, reply, sub].inspect}`!"

            service = data['service']

            Artery.publish(reply, all.map { |obj| obj.to_artery(service) }) # TODO: We MUST optimize this!
          end
        end
      end
    end
  end
end
