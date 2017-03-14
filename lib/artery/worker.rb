module Artery
  class Worker
    class Error < Artery::Error; end

    def execute
      Artery.start do
        tries = 0
        begin
          Artery.models.each do |_model_name, model_class|
            model_subscriptions(model_class)
          end
        rescue Exception => e
          tries += 1
          Artery.handle_error Error.new("WORKER ERROR: #{e.inspect}: #{e.backtrace.join("\n")}")
          retry if tries <= 5

          Artery.handle_error Error.new('Worker failed 5 times and exited.')
        end
      end
    end

    def model_subscriptions(model_class)
      model_class.artery[:subscriptions].each do |uri, options|
        handler = options[:handler]

        # TODO: implement this carefully
        if uri.service != Artery.service_name
          if (lmu_at = Artery.last_model_update_class.last_model_update_at(uri))
            receive_updates(uri, handler, lmu_at) if options[:synchronize_updates]
          elsif options[:synchronize]
            scope = options[:synchronize][:scope] if options[:synchronize].is_a?(Hash)
            receive_all_objects(uri, scope, handler)
          end
        end

        subscribe(uri, handler)
      end
    end

    def subscribe(uri, handler)
      Rails.logger.debug "Subscribing on `#{uri}`"
      Artery.subscribe uri.to_route, queue: "#{Artery.service_name}.worker" do |data, reply, from|
        begin
          handle_subscription(handler, data, reply, from)
        rescue Exception => e
          Artery.handle_error Error.new("Error in subscription handling: #{e.inspect}\n#{e.backtrace.join("\n")}")
        end
      end
    end

    protected

    # rubocop:disable all
    def handle_subscription(handler, data, reply, from)
      Rails.logger.debug "GOT MESSAGE: #{[data, reply, from].inspect}"

      from_uri = Routing.uri(from)

      handle = proc do |d, r, f|
        if data[:updated_by_service].to_s == Artery.service_name.to_s
          Rails.logger.debug 'SKIPPING UPDATES MADE BY US'
          next
        end

        handler.call(from_uri.action, d, r, f) || handler.call(:_default, d, r, f)
      end

      case from_uri.action
      when :create, :update
        get_uri = Routing.uri service: from_uri.service,
                              model: from_uri.model,
                              plural: true,
                              action: :get

        Artery.request get_uri.to_route, { uuid: data['uuid'], service: Artery.service_name }, multihandler: true do |on|
          on.success do |attributes|
            begin
              handle.call(attributes)

              Artery.last_model_update_class.model_update!(from_uri, data[:timestamp])
            rescue Exception => e
              Artery.handle_error Error.new("Error in subscription handler: #{e.inspect}\n#{e.backtrace.join("\n")}")
            end
          end

          on.error do |e|
            error = Error.new("Failed to get #{get_uri.model} from #{get_uri.service} with uuid='#{data[:uuid]}': #{e.message}")
            Artery.handle_error error
          end
        end
      when :delete
        handle.call(data, reply, from)

        Artery.last_model_update_class.model_update!(from_uri, data[:timestamp])
      else
        handle.call(data, reply, from)
      end
    end

    def receive_all_objects(uri, scope, handler)
      uri = Routing.uri(service: uri.service, model: uri.model, plural: true, action: :get_all)
      Artery.request uri.to_route, { service: Artery.service_name, scope: scope }, multihandler: true do |on|
        on.success do |data|
          begin
            Rails.logger.debug "HEY-HEY, ALL OBJECTS: #{[data].inspect}"

            handler.call(:synchronization, data[:objects].map(&:with_indifferent_access))

            Artery.last_model_update_class.model_update!(uri, data[:timestamp])
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
    # rubocop:enable all

    def receive_updates(uri, handler, last_model_update_at)
      uri = Routing.uri(service: uri.service, model: uri.model, plural: true, action: :get_updates)
      Artery.request uri.to_route, { since: last_model_update_at.to_f }, multihandler: true do |on|
        on.success do |data|
          begin
            Rails.logger.debug "HEY-HEY, LAST_UPDATES: #{[data].inspect}"

            data['updates'].each do |update|
              from = Routing.uri(service: uri.service, model: uri.model, action: update.delete('action')).to_route
              handle_subscription(handler, update, nil, from)
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
  end
end
