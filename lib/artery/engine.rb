# frozen_string_literal: true

require 'artery/browser/app'

module Artery
  class Engine < ::Rails::Engine
    isolate_namespace Artery

    endpoint Artery::Browser::App.build

    initializer 'artery.models_reloading' do |app|
      loaders = Rails.autoloaders if Rails.respond_to?(:autoloaders)
      if loaders && (!loaders.respond_to?(:zeitwerk_enabled?) || loaders.zeitwerk_enabled?)
        loaders.main.on_unload { |_cpath, value, _abspath| Artery.unregister_model(value) }
      elsif app.respond_to?(:reloader)
        app.reloader.before_class_unload do
          ActiveSupport::Dependencies.autoloaded_constants.each do |name|
            Artery.unregister_model(name.safe_constantize)
          end
        end
      end
    end

    config.generators do |g|
      g.test_framework      :rspec
      g.fixture_replacement :factory_girl, dir: 'spec/factories'
    end
  end
end
