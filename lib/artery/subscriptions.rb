# frozen_string_literal: true

module Artery
  autoload :Subscription,        'artery/subscription'
  autoload :HealthzSubscription, 'artery/healthz_subscription'
  autoload :WorkerHealthzSubscription, 'artery/worker_healthz_subscription'

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

      def artery_rewind_message_counter!(service:) # rubocop:disable Naming/PredicateMethod
        return false if artery_source_model?

        subscriptions = artery[:subscriptions]&.select do |subscription|
          subscription.uri.service.to_sym == service.to_sym && subscription.synchronize_updates?
        end
        return false if subscriptions.blank?

        subscriptions.each(&:rewind_message_counter!)
        true
      end
    end
  end
end
