# frozen_string_literal: true

Rails.application.routes.draw do
  mount Artery::Engine => '/artery'
end

Rails.application.eager_load!
