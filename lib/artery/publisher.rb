# frozen_string_literal: true

require 'concurrent'

module Artery
  class Publisher
    DISCOVERY_INTERVAL = 5
    POLL_INTERVAL = 30
    BATCH_SIZE = 100

    def run
      Artery.handle_signals { shutdown }
      Artery.start { publisher_loop }
    end

    def shutdown
      @pool&.shutdown
      @pool&.wait_for_termination(10)
    end

    private

    def publisher_loop
      @pool = Concurrent::ThreadPoolExecutor.new(
        min_threads: 1,
        max_threads: ENV.fetch('RAILS_MAX_THREADS', 5).to_i,
        max_queue: 0,
        fallback_policy: :caller_runs
      )
      @known_models = Concurrent::Set.new
      @busy_models = Concurrent::Set.new
      @last_discovery = Time.at(0)

      Instrumentation.instrument(:publisher, action: :started)

      loop do
        discover_models if discovery_due?

        @known_models.each do |model|
          next if @busy_models.include?(model)

          @busy_models.add(model)
          @pool.post { process_model(model) }
        end

        sleep POLL_INTERVAL
      end
    end

    def discover_models
      current = Artery.model_info_class.pluck(:model)

      (@known_models - current).each do |removed|
        @known_models.delete(removed)
        Instrumentation.instrument(:publisher, action: :model_removed, model: removed)
      end

      current.each do |model|
        next if @known_models.include?(model)

        @known_models.add(model)
        Artery.model_info_class.ensure_initialized!(model)
        Instrumentation.instrument(:publisher, action: :model_started, model: model)
      end

      @last_discovery = Time.now
    end

    def discovery_due?
      Time.now - @last_discovery >= DISCOVERY_INTERVAL
    end

    def process_model(model)
      Artery.logger.tagged('Publisher', model) do
        loop do
          published = publish_batch(model)
          break if published < BATCH_SIZE
        end
      end
    rescue StandardError => e
      Instrumentation.instrument(:publisher, action: :error, model: model, error: e.message)
      Artery.handle_error Error.new(
        "Publisher error for #{model}: #{e.message}",
        original_exception: e
      )
    ensure
      @busy_models&.delete(model)
    end

    def publish_batch(model)
      Artery.model_info_class.transaction do
        row = Artery.model_info_class.lock('FOR UPDATE').find_by!(model: model)

        scope = Artery.message_class.where(model: model)
        messages = scope.where(scope.arel_table[:id].gt(row.last_published_id))
                        .order(:id)
                        .limit(BATCH_SIZE)

        return 0 if messages.empty?

        prev_index = row.last_published_id
        Instrumentation.instrument(:publisher, action: :publishing, model: model, count: messages.size) do
          messages.each do |msg|
            msg.publish_to_artery(previous_index: prev_index)
            prev_index = msg.id
          end
        end

        row.update!(last_published_id: prev_index)
        messages.size
      end
    end
  end
end
