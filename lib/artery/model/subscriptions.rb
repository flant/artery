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

        def artery_add_subscription(uri, options = {}, &blk)
          raise ArgumentError, 'block must be provided to handle subscription updates' unless block_given?

          handler ||= Multiblock.wrapper

          if uri.action.blank? || uri.action.to_s == '*'
            yield(handler)
          else
            handler._default(&blk)
          end

          artery[:subscriptions] ||= {}
          artery[:subscriptions][uri] = options.merge(handler: handler)
        end

        def artery_watch_model(service:, model: nil, action: nil, **kwargs, &blk)
          model  ||= artery_model_name
          action ||= '*' # FIXME: This leads to handling GET messages, which is useless reaction

          artery_add_subscription Routing.uri(service: service, model: model, action: action), kwargs, &blk
        end

        # rubocop:disable Metrics/AbcSize
        def artery_add_get_subscriptions
          artery_add_subscription Routing.uri(model: artery_model_name, action: :get) do |data, reply, sub|
            puts "HEY-HEY-HEY, message on GET with arguments: `#{[data, reply, sub].inspect}`!"

            obj = artery_find! data['uuid']
            service = data['service']

            Artery.publish(reply, obj.to_artery(service))
          end

          artery_add_subscription Routing.uri(model: artery_model_name, action: :get_all) do |data, reply, sub|
            puts "HEY-HEY-HEY, message on GET_ALL with arguments: `#{[data, reply, sub].inspect}`!"

            service = data['service']

            Artery.publish(reply, objects: artery_all.map { |obj| obj.to_artery(service) }, timestamp: Time.zone.now.to_f)
          end

          artery_add_subscription Routing.uri(model: artery_model_name, action: :get_updates) do |data, reply, sub|
            puts "HEY-HEY-HEY, message on GET_UPDATES with arguments: `#{[data, reply, sub].inspect}`!"

            messages = Artery.message_class.since(artery_model_name, data['since'])
            puts "MESSAGES: #{messages.inspect}"

            Artery.publish(reply, updates: messages.map { |obj| obj.to_artery.merge('action' => obj.action) })
          end
        end
        # rubocop:enable Metrics/AbcSize
      end
    end
  end
end
