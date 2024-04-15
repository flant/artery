# frozen_string_literal: true

module Artery
  class HealthzSubscription
    attr_reader :id, :name
    def initialize(id, name)
      @id = id
      @name = name
    end

    def subscribe
      healthz_route = "#{Artery.service_name}.#{name}.healthz"
      Artery.logger.debug "Subscribing on '#{healthz_route}' for #{name} #{id}"

      Artery.subscribe healthz_route do |data, reply, _from|
        next unless data['id'] == id

        Artery.publish reply, status: :ok
      end
    end
  end
end
