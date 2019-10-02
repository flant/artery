# frozen_string_literal: true

return unless defined?(::ActiveRecord)

module Artery
  module ActiveRecord
    class Message < ::ActiveRecord::Base
      include MessageModel

      self.table_name = 'artery_messages'

      serialize :data, JSON

      before_save :lock_previous_index
      after_commit :send_to_artery

      alias :index :id

      class << self
        def since(model, since)
          where(model: model)
            .where('created_at > ?', Time.zone.at(since)) # TODO: ZONE? SEARCH IN MCS?
        end

        def after_index(model, index)
          where(model: model)
            .where(arel_table[:id].gt(index)).order(:id)
        end

        def latest_index(model)
          where(model: model).last&.id.to_i
        end

        def delete_old
          where(arel_table[:created_at].lt(MAX_MESSAGE_AGE.ago)).delete_all
        end
      end

      def lock_previous_index
        scope = self.class.where(model: model).order(:id)
        scope = scope.where(self.class.arel_table[:id].lt(index)) if index
        scope = scope.lock

        @previous_index = scope.select(:id).last&.id.to_i
      end

      def previous_index
        @previous_index || lock_previous_index
      end
    end
  end
end
