# frozen_string_literal: true

module Artery
  autoload :Subscription,        'artery/subscription'
  autoload :HealthzSubscription, 'artery/healthz_subscription'

  module Subscriptions
    extend ActiveSupport::Concern
    included do
      class << self
        attr_accessor :subscriptions
      end
    end

    module ClassMethods
      def subscriptions_on(*services)
        services = services.flatten.map(&:to_sym)

        subscriptions.slice(*subscriptions.keys.select { |uri| services.include?(uri.service) })
      end

      def add_subscription(subscription)
        @subscriptions ||= {}
        @subscriptions[subscription.uri] ||= []
        @subscriptions[subscription.uri] << subscription
      end

      def synchronizing_subscriptions
        @synchronizing_subscriptions ||= []
      end

      def clear_synchronizing_subscriptions!
        Artery.synchronizing_subscriptions.dup.each do |s|
          Artery.logger.warn "<#{s.subscriber}> [#{s.uri}] is still synchronizing, clearing.."

          s.synchronization_in_progress!(false)
        end
      end
    end
  end
end
