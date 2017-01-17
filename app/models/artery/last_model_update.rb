if defined?(ActiveRecord)
  module Artery
    class LastModelUpdate < ActiveRecord::Base
      class << self
        def model_update!(uri, timestamp)
          obj = find_or_initialize_by service: uri.service, model: uri.model
          obj.last_message_at = timestamp
          obj.save!
        end

        def last_model_update_at(uri)
          obj = find_by service: uri.service, model: uri.model

          obj.last_message_at if obj
        end
      end
    end
  end
end
