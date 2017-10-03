# frozen_string_literal: true
module Artery
  class Error < StandardError
    attr_accessor :artery_context

    def initialize(message = nil, **context)
      super message

      @original_exception = context.delete(:original_exception)
      @artery_context = context

      set_backtrace @original_exception ? @original_exception.backtrace : caller if backtrace.blank?
    end
  end

  class RequestError < Error
    attr_accessor :uri, :response

    def initialize(uri, response, **context)
      @uri = uri
      @response = response || {}

      super nil, **context
    end

    def message
      response[:error]
    end
  end

  class TimeoutError < Error; end

  class FormatError < Error
    attr_accessor :route, :msg

    def initialize(route, msg, **context)
      @route = route
      @msg = msg

      super nil, **context
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

        options = {
          extra: {}
        }
        options[:extra][:artery] = exception.artery_context if exception.respond_to?(:artery_context)

        Raven.capture_exception(exception, options)
      end
    end
  end

  module_function def handle_error(exception)
    Artery.error_handler.handle exception
  end
end
