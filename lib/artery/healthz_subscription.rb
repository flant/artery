# frozen_string_literal: true

module Artery
  class HealthzSubscription
    def subscribe
      healthz_route = "#{Artery.service_name}.healthz.check"
      Artery.logger.debug "Subscribing on '#{healthz_route}'"

      Artery.subscribe healthz_route, queue: "#{Artery.service_name}.healthz.check" do |_data, reply, _from|
        Artery.publish reply, status: :ok
      end
    end
  end
end
