# frozen_string_literal: true

module Artery
  class Subscription
    module Synchronization
      extend ActiveSupport::Concern

      def synchronize?
        options[:synchronize]
      end

      def synchronize_updates?
        options[:synchronize_updates]
      end

      def synchronization_scope
        options[:synchronize].is_a?(Hash) ? options[:synchronize][:scope] : nil
      end

      def synchronization_per_page
        options[:synchronize].is_a?(Hash) ? options[:synchronize][:per_page] : nil
      end

      def synchronization_in_progress?
        info.synchronization_in_progress?
      end

      def synchronization_in_progress!(val = true)
        if val
          Artery.synchronizing_subscriptions << self
        else
          Artery.synchronizing_subscriptions.delete self
        end

        info.update! synchronization_in_progress: val
      end

      def synchronization_page_update!(page)
        info.update! synchronization_page: page
      end

      def synchronize!
        # TODO: implement this carefully
        return if uri.service == Artery.service_name || synchronization_in_progress?

        if last_model_updated_at && synchronize_updates?
          synchronization_in_progress!
          receive_updates
        elsif !last_model_updated_at && synchronize?
          synchronization_in_progress!
          receive_all
        end
      end

      # rubocop:disable Metrics/AbcSize, Lint/RescueException, Metrics/MethodLength, Metrics/BlockLength
      def receive_all
        all_uri = Routing.uri(service: uri.service, model: uri.model, plural: true, action: :get_all)

        page = info.synchronization_page ? info.synchronization_page + 1 : 0 if synchronization_per_page

        objects = nil

        all_data = {
          service: representation_name, # DEPRECATED: old-style param
          representation: representation_name,
          scope: synchronization_scope,
          page: page,
          per_page: synchronization_per_page
        }

        Artery.request all_uri.to_route, all_data do |on|
          on.success do |data|
            begin
              Artery.logger.debug "HEY-HEY, ALL OBJECTS: #{[data].inspect}"

              objects = data[:objects].map(&:with_indifferent_access)

              handler.call(:synchronization, objects, page)

              if synchronization_per_page && objects.count.positive?
                synchronization_page_update!(page)
                receive_all
              else
                synchronization_page_update!(nil) if synchronization_per_page
                synchronization_in_progress!(false)
                model_update!(data[:timestamp])
              end
            rescue Exception => e
              synchronization_in_progress!(false)
              Artery.handle_error Error.new("Error in all objects request handling: #{e.inspect}",
                                            original_exception: e,
                                            request: {
                                              route: all_uri.to_route,
                                              data: all_data.to_json
                                            },
                                            response: data.to_json)
            end
          end

          on.error do |e|
            synchronization_in_progress!(false)
            error = Error.new "Failed to get all objects #{uri.model} from #{uri.service} with scope='#{synchronization_scope}': "\
                              "#{e.message}", e.artery_context
            Artery.handle_error error
          end
        end
      end

      def receive_updates
        updates_uri = Routing.uri(service: uri.service, model: uri.model, plural: true, action: :get_updates)
        updates_data = { since: last_model_updated_at.to_f }

        Artery.request updates_uri.to_route, updates_data do |on|
          on.success do |data|
            begin
              Artery.logger.debug "HEY-HEY, LAST_UPDATES: #{[data].inspect}"

              data['updates'].each do |update|
                from = Routing.uri(service: uri.service, model: uri.model, action: update.delete('action')).to_route
                handle(update, nil, from)
              end
              synchronization_in_progress!(false)
            rescue Exception => e
              synchronization_in_progress!(false)
              Artery.handle_error Error.new("Error in updates request handling: #{e.inspect}",
                                            original_exception: e,
                                            request: {
                                              route: updates_uri.to_route,
                                              data: updates_data.to_json
                                            },
                                            response: data.to_json)
            end
          end

          on.error do |e|
            synchronization_in_progress!(false)
            Artery.handle_error Error.new("Failed to get updates for #{uri.model} from #{uri.service}: #{e.message}", e.artery_context)
          end
        end
      end
      # rubocop:enable Metrics/AbcSize, Lint/RescueException, Metrics/MethodLength, Metrics/BlockLength
    end
  end
end
