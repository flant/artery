# frozen_string_literal: true

module Artery
  # NATS subjects the service publishes to and subscribes to, derived from its models, subscriptions and
  # declared outgoing routes. Call it after the application has been eager loaded.
  class Permissions
    # Subscriptions that receive these actions request the attributes of the changed record.
    ENRICHED_ACTIONS = %i[* create update].freeze
    PASSWORD_PLACEHOLDER = '__ARTERY_PASSWORD__'

    def service
      Artery.service_name.to_s
    end

    def publish
      routes = ['_INBOX.>']
      routes += healthz_services.map { |name| "#{name}.healthz.check" }
      routes += Artery.models.select(&:artery_source_model?).map { |model| "#{service}.#{model.artery_model_name}.*" }
      routes += subscriptions.values.flatten.select(&:client?).flat_map { |subscription| requests(subscription) }
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
      password_variable ||= "#{service.upcase.gsub(/[^A-Z0-9]/, '_')}_PASSWORD_HASH"
      user = {
        user: service,
        password: PASSWORD_PLACEHOLDER,
        permissions: { publish: { allow: publish }, subscribe: { allow: subscribe } }
      }
      JSON.pretty_generate(user).sub(%("#{PASSWORD_PLACEHOLDER}"), "$#{password_variable}")
    end

    private

    def subscriptions
      Artery.subscriptions || {}
    end

    # `artery-check` requests the essential services, or every service it subscribes to when none is set.
    def healthz_services
      [service] + Artery::Check::ESSENTIAL_SERVICES + subscriptions.keys.map(&:service)
    end

    # Requests a client subscription makes to the source service: see Subscription::IncomingMessage#enrich_data
    # and Subscription::Synchronization.
    def requests(subscription)
      uri = subscription.uri
      actions = []
      actions << :get if ENRICHED_ACTIONS.include?(uri.action)
      actions << :get_updates if subscription.synchronize_updates?
      actions << :get_all if subscription.synchronize? || subscription.rewindable?
      actions.map do |action|
        Routing.uri(service: uri.service, model: uri.model, plural: true, action: action).to_route
      end
    end

    def normalize(routes)
      routes.map(&:to_s).uniq.sort
    end
  end
end
