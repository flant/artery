# frozen_string_literal: true

module Artery
  module ActiveRecord
    class SubscriptionInfo < ::ActiveRecord::Base
      self.table_name = 'artery_subscription_infos'

      class << self
        def find_for_subscription(subscription)
          info = find_or_initialize_by(subscriber: subscription.subscriber.to_s,
                                       service: subscription.uri.service,
                                       model: subscription.uri.model)

          info.save! if info.new_record?
          info
        end
      end

      def synchronization_transaction(&block)
        with_lock(&block)
      end

      def with_lock
        self.class.transaction do
          unless (was_locked = @locked) # prevent double lock to reduce selects
            Artery::Instrumentation.instrument(:lock, state: :waiting, latest_index: latest_index)

            Artery::Instrumentation.instrument(:lock, state: :acquired, latest_index: latest_index) do
              reload lock: true # explicitely reload record
            end

            @locked = true
          end

          yield
        ensure
          @locked = false unless was_locked
        end
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
