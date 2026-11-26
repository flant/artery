# frozen_string_literal: true

module Artery
  # NATS subjects the service publishes to and subscribes to, derived from its models, subscriptions and
  # declared outgoing routes. Call it after the application has been eager loaded.
  class Permissions
    VARIABLE_NAME = /\A[A-Za-z_][A-Za-z0-9_]*\z/.freeze

    # A reference to a nats.conf variable, written unquoted.
    VariableReference = Struct.new(:name) do
      def to_json(*)
        "$#{name}"
      end
    end

    def service
      Artery.service_name.to_s
    end

    # Replies go to the inboxes of the requesters: `_INBOX.>` covers the default prefixes, and an own prefix
    # outside `_INBOX` is added so the service can answer itself. Other prefixes are declared as outgoing routes.
    def publish
      routes = ['_INBOX.>']
      routes << "#{inbox_prefix}.>" unless inbox_prefix == '_INBOX' || inbox_prefix.start_with?('_INBOX.')
      routes += healthz_services.map { |name| "#{name}.healthz.check" }
      routes += Artery.models.select(&:artery_source_model?).map { |model| "#{service}.#{model.artery_model_name}.*" }
      routes += subscriptions.values.flatten.flat_map(&:requested_routes)
      routes += Artery.outgoing_routes
      normalize(routes)
    end

    def subscribe
      routes = ["#{inbox_prefix}.>", "#{service}.healthz.check", "#{service}.healthz.worker"]
      routes += subscriptions.keys.map(&:to_route)
      normalize(routes)
    end

    # A user entry of the `authorization.users` list of nats.conf. The password is a reference to a variable
    # holding its bcrypt hash, so no secret is printed.
    def to_nats_user(password_variable: nil, user: nil)
      password_variable ||= "#{service.upcase.gsub(/[^A-Z0-9]/, '_').sub(/\A(?=\d)/, '_')}_PASSWORD_HASH"
      unless VARIABLE_NAME.match?(password_variable)
        raise ArgumentError, "Invalid password variable name: #{password_variable.inspect}"
      end

      JSON.pretty_generate(
        user: user.presence || service,
        password: VariableReference.new(password_variable),
        permissions: { publish: { allow: publish }, subscribe: { allow: subscribe } }
      )
    end

    private

    def subscriptions
      Artery.subscriptions || {}
    end

    # nats-pure uses `_INBOX` when the backend names no prefix.
    def inbox_prefix
      Artery.backend.inbox_prefix || '_INBOX'
    end

    # Services whose health checks the service may request: itself, `Check::ESSENTIAL_SERVICES` (the default
    # list of `Check#execute`) and the services of its subscriptions (checked when the list is empty, as
    # `artery-check` without arguments does). A wildcard service names no service to check.
    def healthz_services
      subscription_services = subscriptions.keys.map(&:service).reject { |name| name.to_s == '*' }
      [service] + Artery::Check::ESSENTIAL_SERVICES + subscription_services
    end

    def normalize(routes)
      routes.map(&:to_s).uniq.sort
    end
  end
end
