# frozen_string_literal: true

module Artery
  class Subscription
    autoload :Synchronization, 'artery/subscription/synchronization'
    autoload :IncomingMessage, 'artery/subscription/incoming_message'

    include Synchronization

    attr_accessor :uri, :subscriber, :handler, :options

    DEFAULTS = {
      synchronize:         false,
      synchronize_updates: true,
      representation:      Artery.service_name
    }.freeze

    def initialize(model, uri, handler:, **options)
      @uri        = uri
      @subscriber = model
      @handler    = handler
      @options    = DEFAULTS.merge(options)

      Artery.add_subscription self
    end

    def info
      @info ||= Artery.subscription_info_class.find_for_subscription(self)
    end

    def representation_name
      options[:representation]
    end

    def last_model_updated_at
      info.last_message_at
    end

    def latest_message_index
      info.latest_index.to_i
    end

    def new?
      !last_model_updated_at && !latest_message_index.positive?
    end

    def update_info_by_message!(message)
      return if !message.has_index? || message.from_updates?

      new_data = {}
      # DEPRECATED: old-style (pre 0.7)
      new_data[:last_message_at] = Time.zone.at(message.timestamp) if message.timestamp > last_model_updated_at.to_f

      # new-style (since 0.7)
      new_data[:latest_index] = message.index if message.index.positive? && (message.index > latest_message_index)

      info.update! new_data
    end

    def handle(message)
      Artery.logger.debug "GOT MESSAGE: #{message.inspect}"

      unless handler.has_block?(message.action)
        Artery.logger.debug 'SKIPPING MESSAGE WE ARE NOT LISTENING TO'
        return
      end

      info.lock_for_message(message) do
        if !message.from_updates? && synchronization_in_progress?
          Artery.logger.debug 'SKIPPING MESSAGE RECEIVED WHILE SYNC IN PROGRESS'
          return
        end
        return if !message.from_updates? && !validate_index(message)

        if message.update_by_us?
          Artery.logger.debug 'SKIPPING UPDATE MADE BY US'
          update_info_by_message!(message)
          return
        end

        case message.action
        when :create, :update
          message.enrich_data do |attributes|
            handle_data(message, attributes)
          end
        else
          handle_data(message)
        end
      end
    end

    protected

    def validate_index(message)
      return true unless message.previous_index.positive? && latest_message_index.positive?

      if message.previous_index > latest_message_index
        Artery.logger.debug 'WE\'VE GOT FUTURE MESSAGE, REQUESTING ALL MISSED'

        synchronize! # this will include current message
        false
      elsif message.previous_index < latest_message_index
        Artery.logger.debug 'WE\'VE GOT PREVIOUS MESSAGE AND ALREADY HANDLED IT, SKIPPING'

        false
      else
        true
      end
    end

    def handle_data(message, data = nil)
      data ||= message.data

      info.lock_for_message(message) do
        if data == :not_found # special data when enrich failed with not_found
          Artery.logger.debug 'SKIP HANDLING MESSAGE BECAUSE ENRICH DATA IS BLANK'
        else
          handler.call(:_before_action, message.action, data, message.reply, message.from)

          handler.call(message.action,  data, message.reply, message.from) ||
            handler.call(:_default, data, message.reply, message.from)

          handler.call(:_after_action, message.action, data, message.reply, message.from)
        end

        update_info_by_message!(message)
      end
    end
  end
end
