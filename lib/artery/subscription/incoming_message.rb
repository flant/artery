# frozen_string_literal: true

module Artery
  class Subscription
    class IncomingMessage
      attr_accessor :data, :reply, :from, :from_uri, :subscription
      def initialize(subscription, data, reply, from)
        @subscription = subscription
        @data         = data
        @reply        = reply
        @from         = from
        @from_uri     = Routing.uri(@from)
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

      def timestamp
        # DEPRECATED: old-style (pre 0.7)
        data[:timestamp].to_f
      end

      def has_index?
        timestamp.positive? || # DEPRECATED: old-style (pre 0.7)
        index.positive?
      end

      def enrich_data
        get_uri = Routing.uri service: from_uri.service,
                              model: from_uri.model,
                              plural: true,
                              action: :get
        get_data = {
          uuid: data[:uuid],
          representation: subscription.representation_name,
          service: subscription.representation_name # DEPRECATED: old-style param
        }

        Artery.request get_uri.to_route, get_data do |on|
          on.success do |attributes|
            yield attributes
          rescue Exception => e
            error = Error.new("Error in subscription handler: #{e.inspect}",
              original_exception: e,
              subscription: {
                subscriber: subscription.subscriber.to_s,
                data: data.to_json,
                route: from,
              },
              request: { data: get_data.to_json, route: get_uri.to_route }, response: attributes.to_json)
            Artery.handle_error error
          end

          on.error do |e|
            error = Error.new("Failed to get #{get_uri.model} from #{get_uri.service} with uuid='#{data[:uuid]}': #{e.message}",
              e.artery_context.merge(subscription: {
                subscriber: subscription.subscriber.to_s,
                data: data.to_json,
                route: from_uri.to_route,
              })
            )
            Artery.handle_error error
          end
        end
      end

      def inspect
        "<#{from}> <#{reply}> #{data}".inspect
      end
    end
  end
end
