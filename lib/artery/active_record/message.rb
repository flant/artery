# frozen_string_literal: true

module Artery
  module ActiveRecord
    class Message < ::ActiveRecord::Base
      include MessageModel

      self.table_name = 'artery_messages'

      serialize :data, JSON

      around_create :lock_on_model
      after_commit :send_to_artery, on: :create

      alias :index :id

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
          where(arel_table[:id].lteq(max_aged_id)).delete_all if max_aged_id.to_i > 0
        end
      end

      def load_previous_index
        scope = self.class.where(model: model).order(:id)
        scope = scope.where(self.class.arel_table[:id].lt(index)) if index

        @previous_index = scope.select(:id).last&.id.to_i
      end

      def previous_index
        @previous_index || load_previous_index
      end

      protected

      def lock_on_model
        self.class.with_advisory_lock("#{self.class.table_name}:#{model}") do
          load_previous_index

          yield
        end
      end
    end
  end
end
