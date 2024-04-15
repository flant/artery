# frozen_string_literal: true

module Artery
  module NoBrainer
    class SubscriptionInfo
      include ::NoBrainer::Document

      table_config name: 'artery_subscription_infos'

      field :subscriber, type: String, required: true
      field :service,    type: String, required: true
      field :model,      type: String, required: true

      field :latest_index, type: Integer

      field :synchronization_in_progress, type: Boolean, required: true, default: false
      field :synchronization_heartbeat,   type: Time,    required: false
      field :synchronization_page,        type: Integer, required: false

      class << self
        def find_for_subscription(subscription)
          params = {
            subscriber: subscription.subscriber.to_s,
            service: subscription.uri.service,
            model: subscription.uri.model
          }

          info = where(params).first || new(params)

          info.save! if info.new_record?
          info
        end
      end

      def with_lock
        was_locked = @lock.present?

        if was_locked # only 'indexed' messages should lock
          yield
        else
          Artery.logger.debug "WAITING FOR LOCK... [LATEST_INDEX: #{latest_index}]"

          lock = ::NoBrainer::Lock.new("artery_subscription_info:#{model}")

          lock.synchronize do
            Artery.logger.debug "GOT LOCK! [LATEST_INDEX: #{latest_index}]"
            reload # need fresh record

            @lock = lock

            yield
          end
        end
      ensure
        @lock = nil unless was_locked
      end

      def lock_for_message(message, &blk)
        if message.has_index? # only 'indexed' messages should lock
          with_lock(&blk)
        else
          yield
        end
      end
    end
  end
end
