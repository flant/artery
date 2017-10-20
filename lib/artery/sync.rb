# frozen_string_literal: true

module Artery
  class Sync
    class Error < Artery::Error; end

    def execute
      Artery.handle_signals

      if Artery.subscriptions.blank?
        Artery.logger.warn 'No subscriptions defined, exiting...'
        return
      end

      Artery.subscriptions.values.flatten.uniq.each(&:synchronize!)
    end
  end
end
