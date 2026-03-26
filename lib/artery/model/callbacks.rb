# frozen_string_literal: true

module Artery
  module Model
    module Callbacks
      extend ActiveSupport::Concern

      included do
        after_create  :artery_on_create
        after_update  :artery_on_update
        after_destroy :artery_on_destroy

        if respond_to?(:archival?) && archival?
          after_archive   :artery_on_archive
          after_unarchive :artery_on_unarchive
        end

        if artery[:non_atomic_notification]
          after_commit :artery_send_pending_notifications
        else
          before_commit :artery_send_pending_notifications
        end
      end

      def artery_on_create
        artery_pending_notifications << [:create]
      end

      def artery_on_update
        artery_pending_notifications << [:update]
      end

      def artery_on_archive
        artery_pending_notifications << [:archive, { archived_at: archived_at.to_f }]
      end

      def artery_on_unarchive
        artery_pending_notifications << [:unarchive]
      end

      def artery_on_destroy
        artery_pending_notifications << [:delete]
      end

      private

      def artery_pending_notifications
        @artery_pending_notifications ||= []
      end

      def artery_send_pending_notifications
        attempts = 0
        begin
          artery_pending_notifications.each do |action, extra_data|
            artery_notify_message(action, extra_data || {})
          end
        rescue StandardError => e
          attempts += 1
          retry if self.class.artery[:non_atomic_notification] && attempts <= 3

          Artery.handle_error Artery::Error.new(
            "Failed to send artery notifications after #{attempts} attempts: #{e.message}",
            original_exception: e
          )
        ensure
          @artery_pending_notifications = nil
        end
      end
    end
  end
end
