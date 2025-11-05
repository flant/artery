# frozen_string_literal: true

module Artery
  module Model
    module Subscriptions
      extend ActiveSupport::Concern

      ARTERY_MAX_UPDATES_SYNC              = 2000 # we should limit updates fetched at once
      ARTERY_MAX_AUTOENRICHED_UPDATES_SYNC = 500  # we should limit updates fetched at once

      included do
        artery_add_get_subscriptions if artery_source_model?

        attr_accessor :artery_updated_by_service
      end

      module ClassMethods
        def artery_find_all(uuids)
          where "#{artery_uuid_attribute}": uuids
        end

        def artery_find(uuid)
          artery_find_all([uuid]).first
        end

        def artery_resync!
          return false if artery_source_model?

          artery[:subscriptions]&.detect(&:synchronize?)&.receive_all
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
          artery[:subscriptions].push Subscription.new(self, uri, **options.merge(handler: handler))
        end

        def artery_watch_model(service:, model: nil, action: nil, **kwargs, &blk)
          model  ||= artery_model_name
          action ||= '*'

          artery_add_subscription Routing.uri(service: service, model: model, action: action), kwargs, &blk
        end

        # rubocop:disable Metrics/AbcSize,Metrics/MethodLength,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
        def artery_add_get_subscriptions
          artery_add_subscription Routing.uri(model: artery_model_name_plural, action: :get) do |data, reply, sub|
            Artery.logger.info "HEY-HEY-HEY, message on GET with arguments: `#{[data, reply, sub].inspect}`!"
            obj = artery_find data['uuid']

            representation = data['representation']

            data = obj.blank? ? { error: 'not_found' } : obj.to_artery(representation)

            Artery.publish(reply, data)
          end

          artery_add_subscription Routing.uri(model: artery_model_name_plural, action: :get_all) do |data, reply, sub|
            Artery.logger.info "HEY-HEY-HEY, message on GET_ALL with arguments: `#{[data, reply, sub].inspect}`!"

            scope    = "artery_#{data['scope'] || 'all'}"
            per_page = data['per_page']
            page     = data['page'] || 0

            representation = data['representation']

            data = if respond_to?(scope)
                     relation = send(scope)
                     relation = relation.offset(page * per_page).limit(per_page) if per_page
                     objects = relation.map { |obj| obj.to_artery(representation) }
                     {
                       objects: objects,
                       _index: Artery.message_class.latest_index(artery_model_name)
                     }
                   else
                     Artery.logger.error "No artery scope '#{data['scope']}' defined!"
                     { error: 'No such scope!' }
                   end

            Artery.publish(reply, data)
          end

          artery_add_subscription Routing.uri(model: artery_model_name_plural,
                                              action: :get_updates) do |data, reply, sub|
            Artery.logger.info "HEY-HEY-HEY, message on GET_UPDATES with arguments: `#{[data, reply, sub].inspect}`!"

            index = data['after_index'].to_i
            autoenrich = data['representation'].present?
            per_page = data['per_page'] || (autoenrich ? ARTERY_MAX_AUTOENRICHED_UPDATES_SYNC : ARTERY_MAX_UPDATES_SYNC)

            if index.positive?
              messages = Artery.message_class.after_index(artery_model_name, index).limit(per_page)
            else
              Artery.publish(reply, error: :bad_index)
              return
            end

            # Deduplicate
            messages = messages.to_a.group_by { |m| [m.action, m.data] }.values
                               .map { |mm| mm.max_by { |m| m.index.to_i } }
                               .sort_by { |m| m.index.to_i }

            latest_index = Artery.message_class.latest_index(artery_model_name)
            updates_latest_index = messages.last&.index || latest_index

            Artery.logger.info "MESSAGES: #{messages.inspect}"

            # Autoenrich data
            if autoenrich
              scope = "artery_#{data['scope'] || 'all'}"
              autoenrich_data = send(scope).artery_find_all(messages.map { |m| m.data['uuid'] }).to_h do |obj|
                [obj.send(artery_uuid_attribute), obj.to_artery(data['representation'])]
              end
            end

            updates = messages.map do |message|
              upd = message.to_artery.merge('action' => message.action)
              if %i[create update].include?(message.action.to_sym) && # WARNING: duplicated logic with `Subscription#handle`!
                 autoenrich_data &&
                 (attrs = autoenrich_data[message.data['uuid']])
                upd['attributes'] = attrs
              end
              upd
            end

            Artery.publish(reply, updates: updates,
                                  _index: updates_latest_index, _continue: updates_latest_index < latest_index)
          end

          artery_add_subscription Routing.uri(model: artery_model_name_plural, action: :metadata) do |data, reply, sub|
            Artery.logger.info "HEY-HEY-HEY, message on METADATA with arguments: `#{[data, reply, sub].inspect}`!"

            Artery.publish(reply, { _index: Artery.message_class.latest_index(artery_model_name) })
          end
        end
        # rubocop:enable Metrics/AbcSize,Metrics/MethodLength,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
      end

      def artery_updated_by!(service)
        self.artery_updated_by_service = service
      end
    end
  end
end
