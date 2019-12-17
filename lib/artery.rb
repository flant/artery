# frozen_string_literal: true

require 'artery/engine' if defined?(Rails)

require 'artery/errors'
require 'artery/backends/base'

require 'multiblock'
require 'multiblock_has_block'
require 'with_advisory_lock'

module Artery
  autoload :Config,        'artery/config'
  autoload :LoggerProxy,   'artery/logger_proxy'
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
  end

  register_backend :nats,      :NATS
  register_backend :nats_pure, :NATSPure

  use_backend :nats # default

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
