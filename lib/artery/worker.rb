module Artery
  class Worker
    def execute
      Artery.start do
        Artery.models.each do |_model_name, model_class|
          model_subscriptions(model_class)
        end
      end
    end

    def model_subscriptions(model_class)
      model_class.artery[:subscriptions].each do |uri, handler|
        # TODO: implement this carefully
        # unless model_class.artery_source_model?
        #   if (lmu_at = Artery.last_model_update_class.last_model_update_at(uri))
        #     receive_updates(model_class, uri, lmu_at)
        #   else
        #     receive_all_objects(model_class, uri)
        #   end
        # end

        subscribe(uri, handler)
      end
    end

    # rubocop:disable all
    def subscribe(uri, handler)
      puts "Subscribing on `#{uri}`"
      Artery.subscribe uri.to_route, queue: "#{Artery.service_name}.worker" do |data, reply, from|
        puts "GOT MESSAGE: #{[data, reply, from].inspect}"
        from_uri = Routing.uri(from)

        begin
          handle = proc do |d, r, f|
            if handler.is_a?(Hash)
              handler[:handler].call(from_uri.action, d, r, f)
            else
              handler.call(d, r, f)
            end
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

        rescue Exception => e
          puts "WORKER ERROR: #{e.inspect}: #{e.backtrace.inspect}"
        end
      end
    end
    # rubocop:enable all

    def receive_all_objects(_model_class, uri)
      uri = Routing.uri(service: uri.service, model: uri.model, action: :get_all)
      Artery.request uri.to_route, service: Artery.service_name do |data|
        puts "HEY-HEY, ALL OBJECTS: #{[data].inspect}"
        # TODO

        Artery.last_model_update_class.model_update!(uri, data['timestamp'])
      end
    end

    def receive_updates(_model_class, uri, last_model_update_at)
      uri = Routing.uri(service: uri.service, model: uri.model, action: :get_updates)
      Artery.request uri.to_route, since: last_model_update_at.to_f do |data|
        puts "HEY-HEY, LAST_UPDATES: #{[data].inspect}"
        # TODO
      end
    end
  end
end
