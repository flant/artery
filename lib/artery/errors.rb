# frozen_string_literal: true
module Artery
  class Error < StandardError; end

  class RequestError < Error
    attr_accessor :uri, :response

    def initialize(uri, response)
      @uri = uri
      @response = response || {}
    end

    def message
      response[:error]
    end
  end

  class TimeoutError < Error; end

  class FormatError < Error
    attr_accessor :route, :msg

    def initialize(route, msg)
      @route = route
      @msg = msg
    end

    def message
      "Received message from #{route} in wrong format: #{msg}"
    end
  end

  # ErrorHandler
  class ErrorHandler
    def self.handle(exception)
      Artery.logger.error exception.message
    end
  end

  if defined?(Raven)
    class RavenErrorHandler < ErrorHandler
      def self.handle(exception)
        super

        Raven.capture_exception(exception)
      end
    end
  end

  module_function def handle_error(exception)
    Artery.error_handler.handle exception
  end
end
