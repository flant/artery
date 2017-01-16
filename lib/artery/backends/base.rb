module Artery
  module Backends
    class Base
      attr_accessor :config
      def initialize(config = {})
        @config = config
      end

      def start(*args, &blk)
        raise NotImplementedError
      end

      def connect(*args, &blk)
        raise NotImplementedError
      end

      def subscribe(*args, &blk)
        raise NotImplementedError
      end

      def unsubscribe(*args, &blk)
        raise NotImplementedError
      end

      def publish(*args, &blk)
        raise NotImplementedError
      end

      def request(*args, &blk)
        raise NotImplementedError
      end

      def stop(*args, &blk)
        raise NotImplementedError
      end
    end
  end
end
