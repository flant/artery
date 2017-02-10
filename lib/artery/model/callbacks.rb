module Artery
  module Model
    module Callbacks
      extend ActiveSupport::Concern

      included do
        after_create  :artery_on_create
        after_update  :artery_on_update
        after_destroy :artery_on_destroy

        after_archive   :artery_on_archive   if respond_to? :after_archive
        after_unarchive :artery_on_unarchive if respond_to? :after_unarchive
      end

      def artery_on_create
        artery_notify_message(:create)
      end

      def artery_on_update
        artery_notify_message(:update)
      end

      def artery_on_archive
        artery_notify_message(:archive, archived_at: archived_at.to_f)
      end

      def artery_on_unarchive
        artery_notify_message(:unarchive)
      end

      def artery_on_destroy
        artery_notify_message(:delete)
      end
    end
  end
end
