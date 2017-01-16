if defined?(ActiveRecord)
  module Artery
    class Message < ActiveRecord::Base
      serialize :data, JSON

      after_commit :send_to_artery

      protected

      def send_to_artery
        Artery.publish route, data.merge('timestamp' => created_at.to_f)
      end
    end
  end
end
