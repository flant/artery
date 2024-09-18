# frozen_string_literal: true

module Artery
  class Sync
    attr_accessor :sync_id

    def initialize(sync_id)
      @sync_id = sync_id
    end

    def execute(services = nil)
      services = Array.wrap(services).map(&:to_sym)
      subscriptions_on_services = services.blank? ? Artery.subscriptions : Artery.subscriptions_on(services)

      if subscriptions_on_services.blank?
        Artery.logger.warn 'No suitable subscriptions defined, exiting...'
        return
      end

      @sync_fiber = Fiber.new do # all synchroniza tion inside must be synchronous
        subscriptions_on_services.values.flatten.uniq.each(&:synchronize!)
      end
      @sync_fiber.resume
    end

    def self.run(subscriptions)
      sync_id = SecureRandom.hex
      Artery.logger.push_tags('Sync', sync_id)
      Artery::Sync.new(sync_id).execute subscriptions
    ensure
      Artery.clear_synchronizing_subscriptions!
      Artery.logger.pop_tags
    end
  end
end
