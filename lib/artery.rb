require 'artery/engine'
require 'artery/backends/base'

require 'multiblock'

module Artery
  autoload :Config,  'artery/config'
  autoload :Worker,  'artery/worker'
  autoload :Model,   'artery/model'
  autoload :Routing, 'artery/routing'
  autoload :Backend, 'artery/backend'

  extend Config
  extend Backend

  module Backends
    autoload :Base, 'artery/backends/base'
    autoload :NATS, 'artery/backends/nats'
  end

  mattr_accessor :models
  class << self
    def register_model(model_class)
      self.models ||= {}
      self.models[model_class.artery_model_name.to_sym] = model_class
    end
  end
end
