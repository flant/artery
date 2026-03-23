# frozen_string_literal: true

module Artery
  class LogSubscriber < ActiveSupport::LogSubscriber
    def request(event)
      p = event.payload

      case p[:stage]
      when :sent     then debug "[REQ] <#{p[:route]}> #{truncate_body(p[:data])}"
      when :response then debug "[RESP] <#{p[:route]}> #{truncate_body(p[:data])} (#{p[:duration_ms].round(1)}ms)"
      when :error    then warn "[REQ ERR] <#{p[:route]}> #{p[:error]} (#{p[:duration_ms].round(1)}ms)"
      end
    end

    def publish(event)
      debug "[PUB] <#{event.payload[:route]}> #{truncate_body(event.payload[:data])}"
    end

    def message(event)
      p = event.payload

      case p[:stage]
      when :received then debug "[RECV] <#{p[:route]}> #{truncate_body(p[:data])}"
      when :handled  then debug "[DONE] <#{p[:route]}> (#{event.duration.round(1)}ms)"
      when :skipped  then debug "[SKIP] #{p[:reason]}"
      end
    end

    def sync(event)
      p = event.payload

      case p[:stage]
      when :receive_all     then info "[SYNC] receive_all <#{p[:route]}> (#{event.duration.round(1)}ms)"
      when :receive_updates then info "[SYNC] receive_updates <#{p[:route]}> (#{event.duration.round(1)}ms)"
      when :all_objects     then debug "[SYNC] all objects <#{p[:route]}> #{truncate_body(p[:data])}"
      when :updates         then debug "[SYNC] updates <#{p[:route]}> #{truncate_body(p[:data])}"
      when :page            then debug "[SYNC] page #{p[:page]} received for <#{p[:route]}>"
      when :continue        then debug '[SYNC] not all updates received, continuing...'
      end
    end

    def connection(event)
      p = event.payload

      case p[:state]
      when :connected    then info "[Backend] connected to #{p[:server]}"
      when :disconnected then warn '[Backend] disconnected'
      when :reconnected  then info "[Backend] reconnected to #{p[:server]}"
      when :closed       then info '[Backend] connection closed'
      end
    end

    def worker(event)
      p = event.payload

      case p[:action]
      when :started     then info "started (id=#{p[:worker_id]})"
      when :subscribing then debug "[SUB] <#{p[:route]}>"
      end
    end

    def lock(event)
      p = event.payload

      case p[:state]
      when :waiting  then debug "[LOCK] waiting (latest_index: #{p[:latest_index]})"
      when :acquired then debug "[LOCK] acquired (latest_index: #{p[:latest_index]}, #{event.duration.round(1)}ms)"
      end
    end

    private

    def debug(msg)
      return unless Artery.log_messages?

      super
    end

    def truncate_body(data)
      return '' if data.nil?

      json = data.is_a?(String) ? data : data.to_json
      max = Artery.message_body_max_size
      return json if max.nil? || max <= 0 || json.length <= max

      "#{json[0...max]}... (truncated, #{json.length} bytes total)"
    end

    def logger
      Artery.logger
    end
  end
end

Artery::LogSubscriber.attach_to :artery
