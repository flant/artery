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

    # Waits for a condition met by another thread, failing the example when it is not met in time.
    def wait_until(timeout = 5)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      sleep 0.01 until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      raise "Not done in #{timeout} s" unless yield
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
