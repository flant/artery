# frozen_string_literal: true

module Artery
  module ActiveRecord
    class ModelInfo < ::ActiveRecord::Base
      self.table_name = 'artery_model_infos'

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
    end
  end
end
