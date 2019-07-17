# frozen_string_literal: true

return unless defined?(::ActiveRecord)

module Artery
  module ActiveRecord
    class SubscriptionInfo < ::ActiveRecord::Base
      self.table_name = 'artery_subscription_infos'

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

      def with_lock
        self.class.transaction do
          if !(was_locked = @locked) # prevent double lock to reduce selects
            Artery.logger.debug "WAITING FOR LOCK...  [LATEST_INDEX: #{latest_index}]"

            reload lock: true # explicitely reload record

            Artery.logger.debug "GOT LOCK! [LATEST_INDEX: #{latest_index}]"

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
