module Artery
  class Worker
    def execute
      Artery.start do
        Artery.models.each do |model_name, model_class|
          model_class.artery[:subscriptions].each do |route, handler|
            puts "Subscribing on `#{route}`"
            Artery.subscribe route, queue: "#{Artery.service_name}.worker" do |data, reply, from|
              puts "GOT MESSAGE: #{[data, reply, from].inspect}"
              begin
                action = Routing.pick_action(from)
                handle = Proc.new do |d, r, f|
                  if handler.is_a?(Hash)
                    handler[:handler].call(action.to_sym, d, r, f)
                  else
                    handler.call(d, r, f)
                  end
                end

                case action.to_sym
                when :create, :update
                  route = Routing.compile service: Routing.pick_service_name(from),
                                          model: Routing.pick_model_name(from),
                                          action: :get

                  Artery.request route, { uuid: data['uuid'], service: Artery.service_name } do |attributes|
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
        end
      end
    end
  end
end
