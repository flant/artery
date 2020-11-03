# frozen_string_literal: true

return unless defined?(::NoBrainer)

module Artery
  module NoBrainer
    class Message
      include MessageModel
      include ::NoBrainer::Document

      table_config name: 'artery_messages'

      field :created_at_f, type: Float

      field :version, type: String
      field :model,   type: String, required: true
      field :action,  type: String, required: true
      field :data,    type: Hash,   required: true
      field :_index,  type: Integer, index: true

      alias :index :_index

      after_save :send_to_artery

      around_create :lock_on_model
      before_create :assign_index

      class << self
        def since(model, since)
          where(model: model, :created_at_f.gt => since)
        end

        def after_index(model, index)
          where(model: model, :_index.gt => index).order(:_index)
        end

        def latest_index(model)
          where(model: model).max(:_index)&.index.to_i
        end

        def delete_old
          where(:created_at_f.lt => MAX_MESSAGE_AGE.ago.to_f).delete_all
        end
      end

      def _create(options = {})
        now = Time.zone.now
        self.created_at_f = now.to_f.round(6) unless created_at_f_changed?
        super
      end

      def previous_index
        return 0 unless index

        self.class.where(model: model, :_index.lt => index).max(:_index)&.index
      end

      def to_artery
        data.merge('timestamp' => created_at_f, '_index' => index)
      end

      protected

      def lock_on_model
        ::NoBrainer::Lock.new("#{self.class.table_name}:#{model}").synchronize do
          yield
        end
      end

      def assign_index
        self._index = self.class.latest_index(model).next
      end
    end
  end
end
