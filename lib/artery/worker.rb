module Artery
  class Worker
    def execute
      Artery.start do
        begin
          Artery.models.each do |_model_name, model_class|
            model_subscriptions(model_class)
          end
        rescue Exception => e
          puts "WORKER ERROR: #{e.inspect}: #{e.backtrace.inspect}"
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
      puts "Subscribing on `#{uri}`"
      Artery.subscribe uri.to_route, queue: "#{Artery.service_name}.worker" do |data, reply, from|
        begin
          handle_subscription(handler, data, reply, from)
        rescue Exception => e
          Rails.logger.error "Error in subscription handling: #{e.inspect}\n#{e.backtrace}"
        end
      end
    end

    protected

    # rubocop:disable all
    def handle_subscription(handler, data, reply, from)
      puts "GOT MESSAGE: #{[data, reply, from].inspect}"

      if data[:updated_by_service].to_s == Artery.service_name.to_s
        puts 'SKIPPING UPDATES MADE BY US'
        return
      end

      from_uri = Routing.uri(from)

      handle = proc do |d, r, f|
        handler.call(from_uri.action, d, r, f) || handler.call(:_default, d, r, f)
      end

      case from_uri.action
      when :create, :update
        get_uri = Routing.uri service: from_uri.service,
                              model: from_uri.model,
                              plural: true,
                              action: :get

        Artery.request get_uri.to_route, uuid: data['uuid'], service: Artery.service_name do |attributes|
          handle.call(attributes)
        end

        Artery.last_model_update_class.model_update!(from_uri, data['timestamp'])
      when :destroy
        handle.call(data, reply, from)

        Artery.last_model_update_class.model_update!(from_uri, data['timestamp'])
      else
        handle.call(data, reply, from)
      end
    end
    # rubocop:enable all

    def receive_all_objects(uri, scope, handler)
      uri = Routing.uri(service: uri.service, model: uri.model, plural: true, action: :get_all)
      Artery.request uri.to_route, service: Artery.service_name, scope: scope do |data|
        begin
          puts "HEY-HEY, ALL OBJECTS: #{[data].inspect}"

          handler.call(:synchronization, data['objects'].map(&:with_indifferent_access))

          Artery.last_model_update_class.model_update!(uri, data['timestamp'])
        rescue Exception => e
          Rails.logger.error "Error in all objects request handling: #{e.inspect}\n#{e.backtrace}"
        end
      end
    end

    def receive_updates(uri, handler, last_model_update_at)
      uri = Routing.uri(service: uri.service, model: uri.model, plural: true, action: :get_updates)
      Artery.request uri.to_route, since: last_model_update_at.to_f do |data|
        begin

          puts "HEY-HEY, LAST_UPDATES: #{[data].inspect}"

          data['updates'].each do |update|
            from = Routing.uri(service: uri.service, model: uri.model, action: update.delete('action')).to_route
            handle_subscription(handler, update, nil, from)
          end
        rescue Exception => e
          Rails.logger.error "Error in updates request handling: #{e.inspect}\n#{e.backtrace}"
        end
      end
    end
  end
end
