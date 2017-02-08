if defined?(ActiveRecord)
  module Artery
    class LastModelUpdate < ActiveRecord::Base
      class << self
        def model_update!(uri, timestamp)
          obj = find_or_initialize_by service: uri.service, model: uri.model
          obj.update! last_message_at: Time.zone.at(timestamp.to_f) if timestamp.to_f > obj.last_message_at.to_f
        end

        def last_model_update_at(uri)
          find_by(service: uri.service, model: uri.model).try(:last_message_at)
        end
      end
    end
  end
end
