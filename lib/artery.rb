require 'artery/engine' if defined?(Rails)

require 'artery/errors'
require 'artery/backends/base'

require 'multiblock'

module Artery
  autoload :Config,       'artery/config'
  autoload :Worker,       'artery/worker'
  autoload :Model,        'artery/model'
  autoload :Routing,      'artery/routing'
  autoload :Backend,      'artery/backend'
  autoload :Subscription, 'artery/subscription'

  include Config
  include Backend

  module Backends
    autoload :Base, 'artery/backends/base'
    autoload :NATS, 'artery/backends/nats'
  end

  class << self
    attr_accessor :subscriptions

    def add_subscription(subscription)
      @subscriptions ||= []
      @subscriptions << subscription
    end
  end
end
