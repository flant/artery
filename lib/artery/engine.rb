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
        # A class defined in the file of its namespace is unloaded with the namespace.
        loaders.main.on_unload do |cpath, value, _abspath|
          Artery.models.select { |model| model.equal?(value) || model.name.to_s.start_with?("#{cpath}::") }
                .each { |model| Artery.unregister_model(model) }
        end
      elsif !zeitwerk && app.respond_to?(:reloader)
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
