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
        if !model_class.artery_source_model? && options[:synchronize]
          if (lmu_at = Artery.last_model_update_class.last_model_update_at(uri))
            receive_updates(uri, handler, lmu_at)
          else
            receive_all_objects(uri, handler)
          end
        end

        subscribe(uri, handler)
      end
    end

    def subscribe(uri, handler)
      puts "Subscribing on `#{uri}`"
      Artery.subscribe uri.to_route, queue: "#{Artery.service_name}.worker" do |data, reply, from|
        handle_subscription(handler, data, reply, from)
      end
    end

    protected

    def handle_subscription(handler, data, reply, from)
      puts "GOT MESSAGE: #{[data, reply, from].inspect}"
      from_uri = Routing.uri(from)

      handle = proc do |d, r, f|
        handler.call(from_uri.action, d, r, f) || handler.call(:_default, d, r, f)
      end

      case from_uri.action
      when :create, :update
        Artery.last_model_update_class.model_update!(from_uri, data['timestamp'])

        get_uri = Routing.uri service: from_uri.service,
                              model: from_uri.model,
                              action: :get

        Artery.request get_uri.to_route, uuid: data['uuid'], service: Artery.service_name do |attributes|
          handle.call(attributes)
        end
      else
        handle.call(data, reply, from)
      end
    end

    def receive_all_objects(uri, handler)
      uri = Routing.uri(service: uri.service, model: uri.model, action: :get_all)
      Artery.request uri.to_route, service: Artery.service_name do |data|
        puts "HEY-HEY, ALL OBJECTS: #{[data].inspect}"

        handler.call(:syncronization, data['objects'])

        Artery.last_model_update_class.model_update!(uri, data['timestamp'])
      end
    end

    def receive_updates(uri, handler, last_model_update_at)
      uri = Routing.uri(service: uri.service, model: uri.model, action: :get_updates)
      Artery.request uri.to_route, since: last_model_update_at.to_f do |data|
        puts "HEY-HEY, LAST_UPDATES: #{[data].inspect}"

        data['updates'].each do |update|
          from = Routing.uri(service: uri.service, model: uri.model, action: update.delete('action')).to_route
          handle_subscription(handler, update, nil, from)
        end
      end
    end
  end
end
