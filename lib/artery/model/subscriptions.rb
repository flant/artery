# frozen_string_literal: true
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

          artery[:subscriptions] ||= []
          artery[:subscriptions].push Subscription.new(self, uri, options.merge(handler: handler))
        end

        def artery_watch_model(service:, model: nil, action: nil, **kwargs, &blk)
          model  ||= artery_model_name
          action ||= '*'

          artery_add_subscription Routing.uri(service: service, model: model, action: action), kwargs, &blk
        end

        # rubocop:disable Metrics/AbcSize
        def artery_add_get_subscriptions
          artery_add_subscription Routing.uri(model: artery_model_name_plural, action: :get) do |data, reply, sub|
            Artery.logger.info "HEY-HEY-HEY, message on GET with arguments: `#{[data, reply, sub].inspect}`!"
            obj = artery_find data['uuid']
            service = data['service']

            data = obj.blank? ? { error: 'not_found' } : obj.to_artery(service)

            Artery.publish(reply, data)
          end

          artery_add_subscription Routing.uri(model: artery_model_name_plural, action: :get_all) do |data, reply, sub|
            Artery.logger.info "HEY-HEY-HEY, message on GET_ALL with arguments: `#{[data, reply, sub].inspect}`!"

            service  = data['service']
            scope    = "artery_#{data['scope'] || 'all'}"
            per_page = data['per_page']
            page     = data['page'] || 0

            data = if respond_to?(scope)
                     relation = send(scope)
                     relation = relation.offset(page * per_page).limit(per_page) if per_page
                     objects = relation.map { |obj| obj.to_artery(service) }
                     { objects: objects, timestamp: Time.zone.now.to_f }
                   else
                     Artery.logger.error "No artery scope '#{data['scope']}' defined!"
                     { error: 'No such scope!' }
                   end

            Artery.publish(reply, data)
          end

          artery_add_subscription Routing.uri(model: artery_model_name_plural, action: :get_updates) do |data, reply, sub|
            Artery.logger.info "HEY-HEY-HEY, message on GET_UPDATES with arguments: `#{[data, reply, sub].inspect}`!"

            since = (data['since'] * 10**5).ceil.to_f / 10**5 # a little less accuracy

            messages = Artery.message_class.since(artery_model_name, since)
            Artery.logger.info "MESSAGES: #{messages.inspect}"

            Artery.publish(reply, updates: messages.map { |obj| obj.to_artery.merge('action' => obj.action) })
          end
        end
        # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
      end

      def artery_updated_by!(service)
        self.artery_updated_by_service = service
      end
    end
  end
end
