# frozen_string_literal: true

module Artery
  class Subscription
    class IncomingMessage
      attr_accessor :data, :reply, :from, :from_uri, :subscription, :options

      def initialize(subscription, data, reply, from, **options)
        @subscription = subscription
        @data         = data
        @attributes   = data[:attributes]
        @reply        = reply
        @from         = from
        @from_uri     = Routing.uri(@from)
        @options      = options
      end

      def action
        from_uri.action
      end

      def index
        data[:_index].to_i
      end

      def previous_index
        data[:_previous_index].to_i
      end

      def has_index?
        index.positive?
      end

      def from_updates?
        options[:from_updates]
      end

      def update_by_us?
        data[:updated_by_service].to_s == Artery.service_name.to_s
      end

      def enrich_data # rubocop:disable Metrics/AbcSize
        # NO enrich needed as we already have message with attributes
        if @attributes
          yield @attributes
          return
        end

        get_uri = Routing.uri service: from_uri.service,
                              model: from_uri.model,
                              plural: true,
                              action: :get
        get_data = {
          uuid: data[:uuid],
          representation: subscription.representation_name
        }

        Artery.request get_uri.to_route, get_data do |on|
          on.success do |attributes|
            yield attributes
          rescue Exception => e # rubocop:disable Lint/RescueException
            error = Error.new("Error in subscription handler: #{e.inspect}",
                              original_exception: e,
                              subscription: {
                                subscriber: subscription.subscriber.to_s,
                                data: data.to_json,
                                route: from
                              },
                              request: { data: get_data.to_json, route: get_uri.to_route }, response: attributes.to_json)
            Artery.handle_error error
          end

          on.error do |e|
            if e.message == 'not_found'
              yield(:not_found)
            else
              error = Error.new("Failed to get #{get_uri.model} from #{get_uri.service} with uuid='#{data[:uuid]}': #{e.message}",
                                e.artery_context.merge(subscription: {
                                                         subscriber: subscription.subscriber.to_s,
                                                         data: data.to_json,
                                                         route: from_uri.to_route
                                                       }))
              Artery.handle_error error
            end
          end
        end
      end

      def inspect
        "<#{from}> <#{reply}> #{data}".inspect
      end
    end
  end
end
