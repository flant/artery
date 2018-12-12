# frozen_string_literal: true

return unless defined?(::ActiveRecord)

module Artery
  module ActiveRecord
    class Message < ::ActiveRecord::Base
      self.table_name = 'artery_messages'

      serialize :data, JSON

      after_commit :send_to_artery

      alias :index :id

      class << self
        def since(model, since)
          where(model: model)
            .where('created_at > ?', Time.zone.at(since)) # TODO: ZONE? SEARCH IN MCS?
        end

        def after_index(model, index)
          where(model: model)
            .where(arel_table[:id].gt(index))
        end

        def latest_index(model)
          where(model: model).maximum(:id)
        end
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
        data.merge('timestamp' => created_at.to_f, '_index' => index, '_previous_index' => previous_index)
      end

      def previous_index
        self.class.where(model: model)
                  .where(self.class.arel_table[:id].lt(index))
                  .maximum(:id)
      end

      protected

      def send_to_artery
        Artery.publish route, to_artery
      end
    end
  end
end
