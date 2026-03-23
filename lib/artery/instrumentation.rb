# frozen_string_literal: true

module Artery
  module Instrumentation
    NAMESPACE = 'artery'

    module_function

    def instrument(event, payload = {}, &block)
      ActiveSupport::Notifications.instrument("#{event}.#{NAMESPACE}", payload, &block)
    end
  end
end
