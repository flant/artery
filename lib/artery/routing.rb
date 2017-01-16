module Artery
  module Routing
    module_function
    def compile(service: nil, model:, action:)
      service ||= Artery.service_name

      [service, model, action].map(&:to_s).join('.')
    end

    def pick_service_name(route)
      route.split('.').first
    end

    def pick_model_name(route)
      route.split('.').second
    end

    def pick_action(route)
      route.split('.').last
    end
  end
end
