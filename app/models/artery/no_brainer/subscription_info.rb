# frozen_string_literal: true

return unless defined?(::NoBrainer)

module Artery
  module NoBrainer
    class SubscriptionInfo
      include ::NoBrainer::Document

      table_config name: 'artery_subscription_infos'

      field :subscriber,        type: String, required: true
      field :service,           type: String, required: true
      field :model,             type: String, required: true
      field :last_message_at_f, type: Float,  required: false

      field :latest_index, type: Integer

      field :synchronization_in_progress, type: Boolean, required: true, default: false
      field :synchronization_page,        type: Integer, required: false

      class << self
        def find_for_subscription(subscription)
          params = {
            subscriber: subscription.subscriber.to_s,
            service: subscription.uri.service,
            model: subscription.uri.model
          }

          info = where(params).first || new(params)

          # Temporary for easier migration from previous scheme without subscriber
          if info.new_record? && (prev_info = where(service: subscription.uri.service, model: subscription.uri.model).first)
            %i[last_message_at_f synchronization_in_progress synchronization_page].each do |att|
              info.send("#{att}=", prev_info.send(att))
            end
          end

          info.save! if info.new_record?
          info
        end
      end

      def last_message_at
        Time.zone.at(last_message_at_f) if last_message_at_f
      end

      def last_message_at=(val)
        self.last_message_at_f = val.to_f.round(6) # need this to match datetime(6) precision in MySQL in other services
      end

      def with_lock
        was_locked = @lock.present?

        if (was_locked) # only 'indexed' messages should lock
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
