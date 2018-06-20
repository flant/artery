# frozen_string_literal: true

module Artery
  class Subscription
    autoload :Synchronization, 'artery/subscription/synchronization'
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

    def model_update!(timestamp)
      info.update! last_message_at: Time.zone.at(timestamp.to_f) if timestamp.to_f > last_model_updated_at.to_f
    end

    # rubocop:disable all
    def handle(data, reply, from)
      Artery.logger.debug "GOT MESSAGE: #{[data, reply, from].inspect}"

      from_uri = Routing.uri(from)

      handle = proc do |d, r, f|
        if data[:updated_by_service].to_s == Artery.service_name.to_s
          Artery.logger.debug 'SKIPPING UPDATES MADE BY US'
          next
        end

        handler.call(:_before_action, from_uri.action, d, r, f)

        handler.call(from_uri.action, d, r, f) || handler.call(:_default, d, r, f)

        handler.call(:_after_action, from_uri.action, d, r, f)
      end

      case from_uri.action
      when :create, :update
        get_uri = Routing.uri service: from_uri.service,
                              model: from_uri.model,
                              plural: true,
                              action: :get
        get_data = { uuid: data['uuid'], representation: representation_name, service: representation_name } # DEPRECATED: old-style param

        Artery.request get_uri.to_route, get_data do |on|
          on.success do |attributes|
            begin
              handle.call(attributes)

              model_update!(data[:timestamp])
            rescue Exception => e
              error = Error.new("Error in subscription handler: #{e.inspect}",
                original_exception: e,
                subscription: {
                  subscriber: subscriber.to_s,
                  data: data.to_json,
                  route: from,
                },
                request: { data: get_data.to_json, route: get_uri.to_route }, response: attributes.to_json)
              Artery.handle_error error
            end
          end

          on.error do |e|
            error = Error.new("Failed to get #{get_uri.model} from #{get_uri.service} with uuid='#{data[:uuid]}': #{e.message}",
              e.artery_context.merge(subscription: {
                subscriber: subscriber.to_s,
                data: data.to_json,
                route: from,
              })
            )
            Artery.handle_error error
          end
        end
      when :delete
        handle.call(data, reply, from)

        model_update!(data[:timestamp])
      else
        handle.call(data, reply, from)
      end
    end
    # rubocop:enable all
  end
end
