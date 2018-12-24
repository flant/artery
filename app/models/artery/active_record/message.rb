# frozen_string_literal: true

return unless defined?(::ActiveRecord)

module Artery
  module ActiveRecord
    class Message < ::ActiveRecord::Base
      include MessageModel

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
          where(model: model).last&.id.to_i
        end

        def delete_old
          where('created_at < ?', MAX_MESSAGE_AGE.ago).delete_all
        end
      end

      def previous_index
        self.class.where(model: model)
                  .where(self.class.arel_table[:id].lt(index))
                  .select(:id)
                  .last&.id.to_i
      end

    end
  end
end
