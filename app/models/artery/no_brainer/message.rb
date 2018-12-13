# frozen_string_literal: true

return unless defined?(::NoBrainer)

module Artery
  module NoBrainer
    class Message
      include MessageModel
      include ::NoBrainer::Document
      include ::NoBrainer::Document::PrecisionTimestamps

      table_config name: 'artery_messages'

      field :version, type: String
      field :model,   type: String, required: true, index: true
      field :action,  type: String, required: true
      field :data,    type: Hash,   required: true
      field :_index,  type: Integer, index: true

      alias :index :_index

      after_save :send_to_artery

      before_create :assign_index

      class << self
        def since(model, since)
          where(model: model, :created_at_f.gt => since)
        end

        def after_index(model, index)
          where(model: model, :_index.gt => index).with_index(:_index)
        end

        def latest_index(model)
          where(model: model).with_index(:_index).max(:_index).index.to_i
        end
      end

      def created_at_f=(val)
        super(val.round(6))
      end

      def previous_index
        self.class.where(model: model, :_index.lt => index).with_index(:_index).max(:_index).index
      end

      def to_artery
        data.merge('timestamp' => created_at_f, '_index' => index)
      end

      protected

      def assign_index
        ::NoBrainer::Lock.new('artery_messages:index').synchronize do
          self._index = self.class.latest_index(model).next
        end
      end
    end
  end
end
