# frozen_string_literal: true

module Artery
  module ActiveRecord
    autoload :Message,          'artery/active_record/message'
    autoload :ModelInfo,        'artery/active_record/model_info'
    autoload :SubscriptionInfo, 'artery/active_record/subscription_info'
  end
end
