module Artery
  module Model
    module Callbacks
      extend ActiveSupport::Concern

      included do
        after_create  :artery_create_message
        after_update  :artery_update_message
        after_destroy :artery_destroy_message

        after_archive :artery_archive_message if respond_to? :after_archive

        if respond_to? :after_unarchive
          after_unarchive :artery_unarchive_message
        end
      end

      protected

      def artery_create_message
        artery_notify_message(:create)
      end

      def artery_update_message
        artery_notify_message(:update)
      end

      def artery_archive_message
        artery_notify_message(:archive, archived_at: archived_at.to_f)
      end

      def artery_unarchive_message
        artery_notify_message(:unarchive)
      end

      def artery_destroy_message
        artery_notify_message(:delete)
      end

      private

      def artery_notify_message(action, extra_data = {})
        Artery.message_class.create! model: self.class.artery_model_name,
                                     action: action,
                                     #  version: self.class.artery_version, TODO:
                                     data: { uuid: artery_uuid }.merge(extra_data)
      end
    end
  end
end
