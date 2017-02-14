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
end
