# frozen_string_literal: true

module Artery
  class Subscription
    autoload :Synchronization, 'artery/subscription/synchronization'
    autoload :IncomingMessage, 'artery/subscription/incoming_message'

    include Synchronization

    attr_accessor :uri, :subscriber, :handler, :options

    DEFAULTS = {
      synchronize: false,
      synchronize_updates: true,
      representation: Artery.service_name
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

    def latest_message_index
      info.latest_index.to_i
    end

    def source?
      @subscriber.artery[:source]
    end

    def latest_outgoing_message_index
      return unless source?

      Artery.message_class.latest_index(@subscriber.artery_model_name)
    end

    def new?
      !latest_message_index.positive?
    end

    def update_info_by_message!(message)
      return if !message.has_index? || message.from_updates?

      new_data = {}
      new_data[:latest_index] = message.index if message.index.positive? && (message.index > latest_message_index)

      info.update! new_data
    end

    def handle(message) # rubocop:disable Metrics/AbcSize
      request_id = message.reply || SecureRandom.hex(8)
      Artery.logger.tagged(request_id) do
        Artery::Instrumentation.instrument(
          :message, stage: :received, route: message.from, data: message.data, request_id: request_id
        )

        info.lock_for_message(message) do
          if !message.from_updates? && synchronization_in_progress?
            Artery::Instrumentation.instrument(:message, stage: :skipped, reason: 'sync in progress')
            return
          end
          return if !message.from_updates? && !validate_index(message)

          if message.update_by_us?
            Artery::Instrumentation.instrument(:message, stage: :skipped, reason: 'update by us')
            update_info_by_message!(message)
            return
          end

          unless handler.has_block?(message.action) || handler.has_block?(:_default)
            Artery::Instrumentation.instrument(:message, stage: :skipped, reason: 'no listener for action')
            update_info_by_message!(message)
            return
          end

          Artery::Instrumentation.instrument(:message, stage: :handled, route: message.from, request_id: request_id) do
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
      end
    end

    protected

    def validate_index(message)
      return true unless message.previous_index.positive? && latest_message_index.positive?

      if message.previous_index > latest_message_index
        Artery::Instrumentation.instrument(:message, stage: :skipped, reason: 'future message, requesting missed')
        synchronize!
        false
      elsif message.previous_index < latest_message_index
        Artery::Instrumentation.instrument(:message, stage: :skipped, reason: 'duplicate message, already handled')
        false
      else
        true
      end
    end

    def handle_data(message, data = nil)
      data ||= message.data

      info.lock_for_message(message) do
        if data == :not_found
          Artery::Instrumentation.instrument(:message, stage: :skipped, reason: 'enrich data not found')
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
