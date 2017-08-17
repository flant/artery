# frozen_string_literal: true
Rails.application.routes.draw do
  mount Artery::Engine => '/artery'
end
