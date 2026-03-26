# frozen_string_literal: true

module Artery
  module ActiveRecord
    class ModelInfo < ::ActiveRecord::Base
      self.table_name = 'artery_model_infos'

      # @deprecated The +latest_index+ column is no longer maintained.
      #   Use {Artery::ActiveRecord::Message.latest_index} instead.

      # @deprecated No longer used. Publishing is handled by {Artery::Publisher}.
      def self.acquire_lock!(model_name)
        lock_row = lock('FOR UPDATE').find_by(model: model_name)
        return lock_row if lock_row

        begin
          create!(model: model_name, latest_index: Artery.message_class.latest_index(model_name))
        rescue ::ActiveRecord::RecordNotUnique
          # concurrent insert — fine
        end

        lock('FOR UPDATE').find_by!(model: model_name)
      end

      def self.ensure_initialized!(model_name)
        row = find_or_create_by!(model: model_name) do |r|
          r.latest_index = Artery.message_class.latest_index(model_name)
        end

        row.update!(last_published_id: row.latest_index) if row.last_published_id.zero? && row.latest_index.positive?

        row
      end
    end
  end
end
