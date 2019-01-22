# frozen_string_literal: true

module Artery
  module Model
    module Subscriptions
      extend ActiveSupport::Concern

      ARTERY_MAX_UPDATES_SYNC = 2000 # we should limit updates fetched at once

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

            representation = data['representation'] || data['service'] # DEPRECATED: old-style param

            data = obj.blank? ? { error: 'not_found' } : obj.to_artery(representation)

            Artery.publish(reply, data)
          end

          artery_add_subscription Routing.uri(model: artery_model_name_plural, action: :get_all) do |data, reply, sub|
            Artery.logger.info "HEY-HEY-HEY, message on GET_ALL with arguments: `#{[data, reply, sub].inspect}`!"

            scope    = "artery_#{data['scope'] || 'all'}"
            per_page = data['per_page']
            page     = data['page'] || 0

            representation = data['representation'] || data['service'] # DEPRECATED: old-style param

            data = if respond_to?(scope)
                     relation = send(scope)
                     relation = relation.offset(page * per_page).limit(per_page) if per_page
                     objects = relation.map { |obj| obj.to_artery(representation) }
                     {
                       objects: objects,
                       timestamp: Time.zone.now.to_f,
                       _index: Artery.message_class.latest_index(artery_model_name)
                     }
                   else
                     Artery.logger.error "No artery scope '#{data['scope']}' defined!"
                     { error: 'No such scope!' }
                   end

            Artery.publish(reply, data)
          end

          artery_add_subscription Routing.uri(model: artery_model_name_plural, action: :get_updates) do |data, reply, sub|
            Artery.logger.info "HEY-HEY-HEY, message on GET_UPDATES with arguments: `#{[data, reply, sub].inspect}`!"

            since = (data['since'] * 10**5).ceil.to_f / 10**5  if data['since'] # a little less accuracy
            index = data['after_index'].to_i

            if index.positive?
              # new-style (since 0.7)
              messages = Artery.message_class.after_index(artery_model_name, index).limit(ARTERY_MAX_UPDATES_SYNC)
            else
              # DEPRECATED: old-style (before 0.7)
              messages = Artery.message_class.since(artery_model_name, since).limit(ARTERY_MAX_UPDATES_SYNC)
            end

            # Deduplicate
            messages = messages.to_a.group_by { |m| [m.action, m.data] }.values
                                    .map { |mm| mm.sort_by { |m| m.index.to_i }.last }
                                    .sort_by { |m| m.index.to_i }

            latest_index = messages.last.index

            Artery.logger.info "MESSAGES: #{messages.inspect}"

            Artery.publish(reply, updates: messages.map { |obj| obj.to_artery.merge('action' => obj.action) },
                                  _index: latest_index, _continue: latest_index < Artery.message_class.latest_index(artery_model_name))
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
