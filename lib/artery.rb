# frozen_string_literal: true

require_relative 'artery/engine' if defined?(Rails)

require_relative 'artery/errors'
require_relative 'artery/backends/base'

require 'multiblock'
require_relative 'multiblock_has_block'

module Artery
  autoload :Config,        'artery/config'
  autoload :Worker,        'artery/worker'
  autoload :Sync,          'artery/sync'
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

    def handle_signals
      %w[TERM INT].each do |sig|
        trap(sig) do
          puts "Caught #{sig} signal, exiting..."

          yield if block_given?

          exit
        end
      end
    end
  end
end
