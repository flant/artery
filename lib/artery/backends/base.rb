# frozen_string_literal: true

module Artery
  module Backends
    class Base
      attr_accessor :config
      def initialize(config = {})
        @config = config
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

      def stop(*_args)
        raise NotImplementedError
      end
    end
  end
end
