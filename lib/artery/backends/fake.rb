# frozen_string_literal: true

# For the test environment
module Artery
  module Backends
    class Fake < Base
      def start(*_args); end

      def connect(*_args); end

      def subscribe(*_args); end

      def unsubscribe(*_args); end

      def publish(*_args); end

      def request(route, data, opts = {})
        yield if block_given?
      end

      def stop(*_args); end
    end
  end
end
