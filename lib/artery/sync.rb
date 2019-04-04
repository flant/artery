# frozen_string_literal: true

module Artery
  class Sync
    def execute(services = nil)
      services = Array.wrap(services).map(&:to_sym)
      subscriptions_on_services = services.blank? ? Artery.subscriptions : Artery.subscriptions_on(services)

      if subscriptions_on_services.blank?
        Artery.logger.warn 'No suitable subscriptions defined, exiting...'
        return
      end

      subscriptions_on_services.values.flatten.uniq.each(&:synchronize!)
    end
  end
end
