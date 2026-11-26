# frozen_string_literal: true

require 'artery/browser/app'

module Artery
  class Engine < ::Rails::Engine
    isolate_namespace Artery

    endpoint Artery::Browser::App.build

    initializer 'artery.models_reloading' do |app|
      loader = app.autoloaders.main if app.respond_to?(:autoloaders)
      loader.on_unload { |cpath, _value, _abspath| Artery.unregister_model(cpath) } if loader.respond_to?(:on_unload)
    end

    config.generators do |g|
      g.test_framework      :rspec
      g.fixture_replacement :factory_girl, dir: 'spec/factories'
    end
  end
end
