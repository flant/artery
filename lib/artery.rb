# frozen_string_literal: true

require_relative 'artery/engine' if defined?(Rails)

require_relative 'artery/errors'
require_relative 'artery/backends/base'
require_relative 'artery/instrumentation'
require_relative 'artery/log_subscriber'

require 'multiblock'
require_relative 'multiblock_has_block'

module Artery
  autoload :Config,        'artery/config'
  autoload :Publisher,     'artery/publisher'
  autoload :PendingReply,  'artery/pending_reply'
  autoload :Worker,        'artery/worker'
  autoload :Sync,          'artery/sync'
  autoload :Check,         'artery/check'
  autoload :Permissions,   'artery/permissions'
  autoload :Model,         'artery/model'
  autoload :Routing,       'artery/routing'
  autoload :Backend,       'artery/backend'
  autoload :Subscriptions, 'artery/subscriptions'

  include Config
  include Backend
  include Subscriptions

  module Backends
    autoload :Base,     'artery/backends/base'
    autoload :NATS,     'artery/backends/nats'
    autoload :NATSPure, 'artery/backends/nats_pure'
    autoload :Fake,     'artery/backends/fake'
  end

  # ORMs
  autoload :ActiveRecord, 'artery/active_record'
  autoload :NoBrainer,    'artery/no_brainer'

  register_backend :nats_pure, :NATSPure
  register_backend :fake,      :Fake

  use_backend :nats_pure # default

  class << self
    attr_accessor :worker

    # Classes that called `artery_model`. A class reloaded in development replaces the previous one.
    def models
      model_registry.values
    end

    def register_model(model)
      model_registry[model.name || model] = model
      self.unloaded_subscriptions = without_subscriber(unloaded_subscriptions) do |subscriber|
        model.name && subscriber.name == model.name
      end
    end

    # Forgets the models unloaded with a constant: the constant itself and classes defined in its file.
    def unregister_unloaded(name, value)
      models.select { |model| model.equal?(value) || model.name.to_s.start_with?("#{name}::") }
            .each { |model| unregister_model(model) }
    end

    # Forgets a class unloaded by code reloading. Its subscriptions move to `unloaded_subscriptions`.
    def unregister_model(model)
      model_registry.delete_if { |_key, registered| registered.equal?(model) }
      return unless subscriptions

      unloaded = subscriptions.transform_values { |list| list.select { |s| s.subscriber.equal?(model) } }
      # Only the last version of a model is kept, also when an earlier one was not named on registration.
      kept = without_subscriber(unloaded_subscriptions) { |subscriber| model.name && subscriber.name == model.name }
      self.unloaded_subscriptions = kept.merge(unloaded) { |_uri, earlier, added| earlier + added }
                                        .reject { |_uri, list| list.empty? }
      self.subscriptions = without_subscriber(subscriptions) { |subscriber| subscriber.equal?(model) }
    end

    # Subscriptions of models unloaded by code reloading and not loaded again yet. A running worker keeps handling
    # their messages until the model registers its subscriptions again.
    def unloaded_subscriptions
      @unloaded_subscriptions ||= {}
    end

    def handle_signals
      %w[TERM INT].each do |sig|
        trap(sig) do
          Artery.logger.info "Caught #{sig} signal, exiting..."

          yield if block_given?

          exit
        end
      end
    end

    private

    attr_writer :unloaded_subscriptions

    # The lists are replaced, not changed, as other threads may be reading them.
    def without_subscriber(registry, &unwanted)
      registry.transform_values { |list| list.reject { |subscription| unwanted.call(subscription.subscriber) } }
              .reject { |_uri, list| list.empty? }
    end

    def model_registry
      @model_registry ||= {}
    end
  end
end
