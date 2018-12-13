module Artery
  module MessageModel
    extend ActiveSupport::Concern

    included do
    end

    module ClassMethods
      def since(model, since)
        raise NotImplementedError
      end

      def after_index(model, index)
        raise NotImplementedError
      end

      def latest_index(model)
        raise NotImplementedError
      end
    end

    def uri
      Artery::Routing.uri(model: model, action: action)
    end

    def uri=(uri)
      self.model   = uri.model
      self.action  = uri.action
    end

    def route
      uri.to_route
    end

    def to_artery
      data.merge('timestamp' => created_at.to_f, '_index' => index)
    end

    def previous_index
      raise NotImplementedError
    end

    protected

    def send_to_artery
      Artery.publish route, to_artery.merge( '_previous_index' => previous_index)
    end
  end
end
