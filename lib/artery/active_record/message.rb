# frozen_string_literal: true

module Artery
  module ActiveRecord
    class Message < ::ActiveRecord::Base
      include MessageModel

      self.table_name = 'artery_messages'

      serialize :data, coder: JSON

      after_commit :send_to_artery, on: :create

      alias index id

      class << self
        def after_index(model, index)
          where(model: model)
            .where(arel_table[:id].gt(index)).order(:id)
        end

        def latest_index(model)
          where(model: model).last&.id.to_i
        end

        def delete_old
          max_aged_id = where(arel_table[:created_at].lt(MAX_MESSAGE_AGE.ago)).maximum(:id)
          where(arel_table[:id].lteq(max_aged_id)).delete_all if max_aged_id.to_i.positive?
        end
      end

      # It is used in after_commit, so we always know previous index based on our current index
      def previous_index
        scope = self.class.where(model: model).order(:id)
        scope = scope.where(self.class.arel_table[:id].lt(index)) if index

        scope.select(:id).last&.id.to_i
      end
    end
  end
end
