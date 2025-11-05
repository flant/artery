module Nats
  module Methods
    def make_request(url, data = {})
      Artery.request(url, data) do |on|
        on.success { |result| result }
        on.error { |error| raise(error) }
      end
    end

    def with_worker(&)
      Fiber.set_scheduler(Async::Scheduler.new)
      f = Fiber.schedule do
        Artery::Worker.new.run
      end

      yield

      f.raise Async::Stop
    end
  end
end
