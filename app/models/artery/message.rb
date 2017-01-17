if defined?(ActiveRecord)
  module Artery
    class Message < ActiveRecord::Base
      serialize :data, JSON

      after_commit :send_to_artery

      def self.since(model, since)
        where(model: model)
          .where('created_at > ?', Time.zone.at(since)) # TODO: ZONE? SEARCH IN MCS?
          .to_a.group_by { |m| [m.action, m.data] }.values.map(&:last)
      end

      def uri
        Artery::Routing.uri(model: model, action: action)
      end

      def uri=(uri)
        self.model   = uri.model
        self.action  = uri.action
      end

      def route
        uri.to_route
      end

      def to_artery
        data.merge('timestamp' => created_at.to_f)
      end

      protected

      def send_to_artery
        Artery.publish route, to_artery
      end
    end
  end
end
