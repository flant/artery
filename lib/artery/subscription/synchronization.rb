module Artery
  class Subscription
    module Synchronization
      extend ActiveSupport::Concern

      def synchronize!
        # TODO: implement this carefully
        return if uri.service == Artery.service_name

        if last_model_updated_at
          receive_updates if options[:synchronize_updates]
        elsif options[:synchronize]
          receive_all
        end
      end

      # rubocop:disable Metrics/AbcSize, Lint/RescueException
      def receive_all
        all_uri = Routing.uri(service: uri.service, model: uri.model, plural: true, action: :get_all)

        Artery.request all_uri.to_route, service: Artery.service_name, scope: options[:scope] do |on|
          on.success do |data|
            begin
              Artery.logger.debug "HEY-HEY, ALL OBJECTS: #{[data].inspect}"

              handler.call(:synchronization, data[:objects].map(&:with_indifferent_access))

              model_update!(data[:timestamp])
            rescue Exception => e
              Artery.handle_error Error.new("Error in all objects request handling: #{e.inspect}\n#{e.backtrace}")
            end
          end

          on.error do |e|
            error = Error.new("Failed to get all objects #{uri.model} from #{uri.service} with scope='#{scope}': #{e.message}")
            Artery.handle_error error
          end
        end
      end

      def receive_updates
        updates_uri = Routing.uri(service: uri.service, model: uri.model, plural: true, action: :get_updates)

        Artery.request updates_uri.to_route, since: last_model_updated_at.to_f do |on|
          on.success do |data|
            begin
              Artery.logger.debug "HEY-HEY, LAST_UPDATES: #{[data].inspect}"

              data['updates'].each do |update|
                from = Routing.uri(service: uri.service, model: uri.model, action: update.delete('action')).to_route
                handle(update, nil, from)
              end
            rescue Exception => e
              Artery.handle_error Error.new("Error in updates request handling: #{e.inspect}\n#{e.backtrace.join("\n")}")
            end
          end

          on.error do |e|
            Artery.handle_error Error.new("Failed to get updates for #{uri.model} from #{uri.service}: #{e.message}")
          end
        end
      end
      # rubocop:enable Metrics/AbcSize, Lint/RescueException
    end
  end
end
