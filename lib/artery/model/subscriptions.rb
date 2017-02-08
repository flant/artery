module Artery
  module Model
    module Subscriptions
      extend ActiveSupport::Concern

      included do
        artery_add_get_subscriptions if artery_source_model?

        attr_accessor :artery_updated_by_service
      end

      module ClassMethods
        def artery_find(uuid)
          find_by "#{artery_uuid_attribute}": uuid
        end

        def artery_add_subscription(uri, options = {}, &blk)
          raise ArgumentError, 'block must be provided to handle subscription updates' unless block_given?

          handler ||= Multiblock.wrapper

          if uri.action.blank? || uri.action.to_s == '*'
            yield(handler)
          else
            handler._default(&blk)
          end

          defaults = {
            synchronize:         false,
            synchronize_updates: true
          }

          options.reverse_merge!(defaults)

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
          artery_add_subscription Routing.uri(model: artery_model_name_plural, action: :get) do |data, reply, sub|
            puts "HEY-HEY-HEY, message on GET with arguments: `#{[data, reply, sub].inspect}`!"
            obj = artery_find data['uuid']
            service = data['service']

            data = obj.blank? ? { error: 'not_found' } : obj.to_artery(service)

            Artery.publish(reply, data)
          end

          artery_add_subscription Routing.uri(model: artery_model_name_plural, action: :get_all) do |data, reply, sub|
            puts "HEY-HEY-HEY, message on GET_ALL with arguments: `#{[data, reply, sub].inspect}`!"

            service = data['service']
            scope   = "artery_#{data['scope'] || 'all'}"

            objects = send(scope).map { |obj| obj.to_artery(service) }

            Artery.publish(reply, objects: objects, timestamp: Time.zone.now.to_f)
          end

          artery_add_subscription Routing.uri(model: artery_model_name_plural, action: :get_updates) do |data, reply, sub|
            puts "HEY-HEY-HEY, message on GET_UPDATES with arguments: `#{[data, reply, sub].inspect}`!"

            messages = Artery.message_class.since(artery_model_name, data['since'])
            puts "MESSAGES: #{messages.inspect}"

            Artery.publish(reply, updates: messages.map { |obj| obj.to_artery.merge('action' => obj.action) })
          end
        end
        # rubocop:enable Metrics/AbcSize
      end

      def artery_updated_by!(service)
        self.artery_updated_by_service = service
      end
    end
  end
end
