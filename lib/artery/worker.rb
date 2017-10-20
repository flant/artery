# frozen_string_literal: true

module Artery
  class Worker
    class Error < Artery::Error; end

    def subscribe_healthz
      healthz_route = "#{Artery.service_name}.worker.healthz"
      Artery.logger.debug "Subscribing on '#{healthz_route}'"

      Artery.subscribe healthz_route do |_data, reply, _from|
        Artery.publish reply, status: :ok
      end
    end

    # rubocop:disable Metrics/AbcSize, Lint/RescueException, Metrics/BlockLength
    def run
      if Artery.subscriptions.blank?
        Artery.logger.warn 'No subscriptions defined, exiting...'
        return
      end

      Artery.handle_signals

      @sync = Artery::Sync.new

      Artery.start do
        tries = 0
        begin
          subscribe_healthz

          @sync.execute

          Artery.subscriptions.each do |uri, subscriptions|
            Artery.logger.debug "Subscribing on '#{uri}'"
            Artery.subscribe uri.to_route, queue: "#{Artery.service_name}.worker" do |data, reply, from|
              subscriptions.each do |subscription|
                begin
                  subscription.handle(data, reply, from)
                rescue Exception => e
                  Artery.handle_error Error.new("Error in subscription handling: #{e.inspect}",
                                                original_exception: e,
                                                subscription: {
                                                  subscriber: subscription.subscriber.to_s,
                                                  route: from,
                                                  data: data.to_json
                                                })
                end
              end
            end
          end
        rescue Exception => e
          tries += 1

          Artery.handle_error Error.new("WORKER ERROR: #{e.inspect}", original_exception: e)
          retry if tries <= 5

          Artery.handle_error Error.new('Worker failed 5 times and exited.')
        end
      end
    ensure
      Artery.clear_synchronizing_subscriptions!
    end
    # rubocop:enable Metrics/AbcSize, Lint/RescueException, Metrics/BlockLength
  end
end
