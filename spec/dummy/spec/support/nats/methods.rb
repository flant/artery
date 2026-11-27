module Nats
  module Methods
    def make_request(url, data = {})
      Artery.request(url, data) do |on|
        on.success { |result| result }
        on.error { |error| raise(error) }
      end
    end

    # Waits for the error reports posted so far; the reporter takes no more afterwards.
    def wait_for_reports(backend)
      reporter = backend.error_reporter
      reporter.shutdown
      raise 'NATS error reports not done in 5 s' unless reporter.wait_for_termination(5)
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
