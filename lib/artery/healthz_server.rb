# frozen_string_literal: true

module Artery
  class HealthzServer
    def initialize(**opts)
      @port = opts.fetch(:port, Artery.healthz_server[:port])
      @bind = opts.fetch(:bind, Artery.healthz_server[:bind_address])
      @verbose = opts.fetch(:verbose, true)
      @log_target = opts[:log_target]
    end

    def setup_server
      begin
        require 'webrick'
      rescue LoadError
        warn '[Artery] WEBrick is not available, health check endpoint will not be started'
        return
      end

      @access_log, @logger = nil

      if @verbose
        @access_log = [
          [$stderr, WEBrick::AccessLog::COMMON_LOG_FORMAT],
          [$stderr, WEBrick::AccessLog::REFERER_LOG_FORMAT]
        ]
        @logger = WEBrick::Log.new(@log_target || $stderr)
      else
        @access_log = []
        @logger = WEBrick::Log.new(@log_target || File::NULL)
      end

      @server =
        WEBrick::HTTPServer.new(
          Port: @port,
          BindAddress: @bind,
          Logger: @logger,
          AccessLog: @access_log
        )

      @server.mount_proc '/' do |_req, res|
        res['Content-Type'] = 'text/plain; charset=utf-8'

        result = Artery::Check.new.execute
        errors = result.select { |_service, res| res[:status] == :error }
        if errors.blank?
          res.status = 200
        else
          res.status = 500
          res.body = "Errors connecting Artery servers:\n\n#{errors.map do |service, check|
            "#{service}: #{check[:message]}"
          end.join("\n")}\n"
        end
      end
    end

    def start
      @runner ||= begin # rubocop:disable Naming/MemoizedInstanceVariableName
        setup_server

        Thread.start do
          @server&.start

          @logger.info '[Artery] [HealthzServer] Started.'
        rescue StandardError => e
          @logger.error "[Artery] [HealthzServer] Failed to start server on port #{@port}: #{e}"
        end
      end
    end
  end
end
