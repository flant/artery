# frozen_string_literal: true

if defined?(ActiveRecord)
  module Artery
    class SubscriptionInfo < ActiveRecord::Base
      class << self
        def find_for_subscription(subscription)
          info = find_or_initialize_by(subscriber: subscription.subscriber.to_s,
                                       service: subscription.uri.service,
                                       model: subscription.uri.model)

          # Temporary for easier migration from previous scheme without subscriber
          if info.new_record? && (prev_info = find_by(service: subscription.uri.service, model: subscription.uri.model))
            %i[last_message_at synchronization_in_progress synchronization_page].each do |att|
              info.send("#{att}=", prev_info.send(att))
            end
          end

          info
        end
      end
    end
  end
end
