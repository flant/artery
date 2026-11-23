# frozen_string_literal: true

module Artery
  module PendingReply
    module_function

    # A synchronous nested delivery must restore the enclosing delivery's inbox.
    def unanswered?(reply)
      previous = Thread.current[:artery_pending_reply]
      Thread.current[:artery_pending_reply] = reply.presence
      yield
      Thread.current[:artery_pending_reply].present?
    ensure
      Thread.current[:artery_pending_reply] = previous
    end

    def published(route)
      Thread.current[:artery_pending_reply] = nil if Thread.current[:artery_pending_reply] == route
    end
  end
end
