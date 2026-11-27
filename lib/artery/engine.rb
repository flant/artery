# frozen_string_literal: true

require 'artery/browser/app'

module Artery
  class Engine < ::Rails::Engine
    isolate_namespace Artery

    endpoint Artery::Browser::App.build

    initializer 'artery.models_reloading' do |app|
      loaders = Rails.autoloaders if Rails.respond_to?(:autoloaders)
      zeitwerk = loaders && (!loaders.respond_to?(:zeitwerk_enabled?) || loaders.zeitwerk_enabled?)
      if zeitwerk && loaders.main.respond_to?(:on_unload)
        loaders.main.on_unload { |cpath, value, _abspath| Artery.unregister_unloaded(cpath, value) }
      elsif app.respond_to?(:reloader)
        # Zeitwerk before 2.5 has no on_unload; both loaders list the constants they are about to unload.
        app.reloader.before_class_unload do
          names = zeitwerk ? loaders.main.unloadable_cpaths : ActiveSupport::Dependencies.autoloaded_constants
          names.each { |name| Artery.unregister_unloaded(name, name.safe_constantize) }
        end
      end
    end

    config.generators do |g|
      g.test_framework      :rspec
      g.fixture_replacement :factory_girl, dir: 'spec/factories'
    end
  end
end
