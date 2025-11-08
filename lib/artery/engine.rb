# frozen_string_literal: true

require "artery/browser/app"

module Artery
  class Engine < ::Rails::Engine
    isolate_namespace Artery

    endpoint Artery::Browser::App.build

    config.generators do |g|
      g.test_framework      :rspec
      g.fixture_replacement :factory_girl, dir: 'spec/factories'
    end
  end
end
