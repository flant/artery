# frozen_string_literal: true

module Artery
  module Backends
    # For the test environment. Requests get the replies prepared with `reply` and `time_out`, an empty one
    # otherwise. The strict mode, enabled by `strict_permissions` in `backend_config` or by
    # ARTERY_STRICT_PERMISSIONS=1, raises `Artery::PermissionDenied` for a request, publish or subscription the
    # service has no permission for in `Artery::Permissions`, before a prepared reply is returned.
    class Fake < Base
      HINTS = {
        publish: 'declare the routes it requests or publishes directly with Artery.add_outgoing_routes',
        subscribe: 'subscribe with artery_watch_model in a model'
      }.freeze

      def initialize(config = {})
        super
        @replies = {}
        return if !strict_permissions? || Artery.service_name?

        raise Error, 'Strict permissions of the fake backend need Artery.service_name'
      end

      def reply(route, data)
        @replies[route.to_s] = data
      end

      def time_out(route)
        @replies[route.to_s] = :timeout
      end

      def clear_replies
        @replies.clear
      end

      def strict_permissions?
        %w[1 true].include?(config.fetch(:strict_permissions) { ENV.fetch('ARTERY_STRICT_PERMISSIONS', nil) }.to_s)
      end

      def start(*_args); end

      def connect(*_args); end

      def subscribe(route = nil, *_args)
        check_permission(:subscribe, route)
      end

      def unsubscribe(*_args); end

      def publish(route = nil, *_args)
        check_permission(:publish, route)
      end

      def request(route, data, _opts = {})
        check_permission(:publish, route)
        return unless block_given?

        reply = @replies[route.to_s]
        return yield(TimeoutError.new(request: { route: route, data: data })) if reply == :timeout

        yield(reply.nil? || reply.is_a?(String) ? reply : reply.to_json)
      end

      def stop(*_args); end

      private

      def check_permission(operation, subject)
        return unless strict_permissions?

        # Models and subscriptions register when their classes load; tests load them lazily.
        @application_loaded ||= Permissions.load_application || true
        return if Permissions.new.permits?(operation, subject)

        raise PermissionDenied, "#{Artery.service_name} has no permission to #{operation} to #{subject}: " \
                                "#{HINTS.fetch(operation)}"
      end
    end
  end
end
