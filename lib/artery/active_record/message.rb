# frozen_string_literal: true

module Artery
  module ActiveRecord
    class Message < ::ActiveRecord::Base
      include MessageModel

      self.table_name = 'artery_messages'

      serialize :data, coder: JSON

      after_commit :send_to_artery, on: :create
      around_create :lock_on_model

      attr_accessor :cached_previous_index

      alias index id

      class << self
        def after_index(model, index)
          where(model: model)
            .where(arel_table[:id].gt(index)).order(:id)
        end

        def latest_index(model)
          Artery.model_info_class.find_by(model: model)&.latest_index.to_i
        end

        def delete_old
          max_aged_id = where(arel_table[:created_at].lt(MAX_MESSAGE_AGE.ago)).maximum(:id)
          where(arel_table[:id].lteq(max_aged_id)).delete_all if max_aged_id.to_i.positive?
        end
      end

      def previous_index
        return cached_previous_index if cached_previous_index

        scope = self.class.where(model: model).order(:id)
        scope = scope.where(self.class.arel_table[:id].lt(index)) if index

        scope.select(:id).last&.id.to_i
      end

      private

      def lock_on_model
        lock_row = Artery.model_info_class.acquire_lock!(model)
        self.cached_previous_index = lock_row.latest_index
        yield
        lock_row.update!(latest_index: id)
      end
    end
  end
end
