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

      result = {}

      services.each do |service|
        Artery.request "#{service}.healthz.check", {}, timeout: @timeout do |on|
          on.success { result[service] = { status: :ok } }
          on.error { |e| result[service] = { status: :error, message: e } }
        end
      end

      result
    end

    def self.run(services)
      Artery.logger.push_tags('Check')
      result = Artery::Check.new.execute services

      errors = result.select { |_service, res| res[:status] == :error }
      return if errors.blank?

      Artery.logger.error "There were errors:\n\t#{errors.map do |service, result|
        "#{service}: #{result[:message]}"
      end.join("\n\t")}"
      exit 1
    ensure
      Artery.logger.pop_tags
    end
  end
end
