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

    def publish
      routes = ['_INBOX.>']
      routes += healthz_services.map { |name| "#{name}.healthz.check" }
      routes += Artery.models.select(&:artery_source_model?).map { |model| "#{service}.#{model.artery_model_name}.*" }
      routes += subscriptions.values.flatten.flat_map(&:requested_routes)
      routes += Artery.outgoing_routes
      normalize(routes)
    end

    def subscribe
      routes = ["#{Artery.backend.inbox_prefix || '_INBOX'}.>", "#{service}.healthz.check", "#{service}.healthz.worker"]
      routes += subscriptions.keys.map(&:to_route)
      normalize(routes)
    end

    # A user entry of the `authorization.users` list of nats.conf. The password is a reference to a variable
    # holding its bcrypt hash, so no secret is printed.
    def to_nats_user(password_variable: nil)
      password_variable ||= "#{service.upcase.gsub(/[^A-Z0-9]/, '_').sub(/\A(?=\d)/, '_')}_PASSWORD_HASH"
      unless VARIABLE_NAME.match?(password_variable)
        raise ArgumentError, "Invalid password variable name: #{password_variable.inspect}"
      end

      JSON.pretty_generate(
        user: Artery.backend.auth_user || service,
        password: VariableReference.new(password_variable),
        permissions: { publish: { allow: publish }, subscribe: { allow: subscribe } }
      )
    end

    private

    def subscriptions
      Artery.subscriptions || {}
    end

    # `artery-check` requests the essential services, or every service it subscribes to when none is set.
    def healthz_services
      [service] + Artery::Check::ESSENTIAL_SERVICES + subscriptions.keys.map(&:service)
    end

    def normalize(routes)
      routes.map(&:to_s).uniq.sort
    end
  end
end
