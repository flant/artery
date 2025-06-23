# frozen_string_literal: true

module Artery
  class Check
    TIMEOUT = ENV.fetch('ARTERY_CHECK_TIMEOUT', '1').to_i

    def initialize(**options)
      @timeout = options.fetch(:timeout, TIMEOUT)
    end

    def execute(services = [])
      all_services = Artery.subscriptions.blank? ? [] : Artery.subscriptions.keys.map(&:service).uniq
      services = all_services if services.blank?

      if services.blank?
        Artery.logger.warn 'No services privided, exiting...'
        return
      end

      errors = {}

      services.each do |service|
        Artery.request "#{service}.healthz.check", {}, timeout: @timeout do |on|
          on.error { |e| errors[service] = e }
        end
      end

      errors
    end

    def self.run(services)
      Artery.logger.push_tags('Check')
      errors = Artery::Check.new.execute services

      return if errors.blank?

      Artery.logger.error "There were errors:\n\t#{errors.map { |service, error| "#{service}: #{error}" }.join("\n\t")}"
      exit 1
    ensure
      Artery.logger.pop_tags
    end
  end
end
