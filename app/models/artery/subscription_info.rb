# frozen_string_literal: true
if defined?(ActiveRecord)
  module Artery
    class SubscriptionInfo < ActiveRecord::Base
      class << self
        def find_for_subscription(subscription)
          find_or_initialize_by(service: subscription.uri.service, model: subscription.uri.model)
        end
      end
    end
  end
end
