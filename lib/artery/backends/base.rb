# frozen_string_literal: true

module Artery
  module Backends
    class Base
      attr_accessor :config

      def initialize(config = {})
        @config = config
      end

      # User name of password authentication; nil for token authentication or none.
      def auth_user; end

      # Prefix of the inboxes that receive replies to requests; nil keeps the default of the client library.
      # Restricted NATS users may subscribe only to inboxes of their own service.
      def inbox_prefix
        config[:inbox_prefix].presence || ENV['ARTERY_INBOX_PREFIX'].presence ||
          ("_INBOX.#{Artery.service_name}" if Artery.service_name?)
      end

      def start(*_args)
        raise NotImplementedError
      end

      def connect(*_args)
        raise NotImplementedError
      end

      def subscribe(*_args)
        raise NotImplementedError
      end

      def unsubscribe(*_args)
        raise NotImplementedError
      end

      def publish(*_args)
        raise NotImplementedError
      end

      def request(*_args)
        raise NotImplementedError
      end

      # Blocks until the server has processed everything sent before, so its errors have been received.
      # A no-op by default, so that backends written before it keep working.
      def flush(*_args); end

      def stop(*_args)
        raise NotImplementedError
      end
    end
  end
end
