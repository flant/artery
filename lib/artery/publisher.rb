# frozen_string_literal: true

require 'concurrent'

module Artery
  class Publisher
    DISCOVERY_INTERVAL = 5
    POLL_INTERVAL = 0.5
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
      @running_models = Concurrent::Set.new

      loop do
        models = Artery.model_info_class.pluck(:model)

        models.each do |model|
          next if @running_models.include?(model)

          @running_models.add(model)
          @pool.post { model_loop(model) }
        end

        sleep DISCOVERY_INTERVAL
      end
    end

    def model_loop(model)
      Artery.model_info_class.ensure_initialized!(model)

      loop do
        published = publish_batch(model)
        sleep POLL_INTERVAL if published < BATCH_SIZE
      end
    rescue StandardError => e
      Artery.handle_error Error.new(
        "Publisher error for #{model}: #{e.message}",
        original_exception: e
      )
      sleep POLL_INTERVAL
      retry
    ensure
      @running_models.delete(model)
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
        messages.each do |msg|
          msg.publish_to_artery(previous_index: prev_index)
          prev_index = msg.id
        end

        row.update!(last_published_id: prev_index)
        messages.size
      end
    end
  end
end
