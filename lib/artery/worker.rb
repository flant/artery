module Artery
  class Worker
    class Error < Artery::Error; end

    def execute
      if Artery.subscriptions.blank?
        Artery.logger.warn 'No subscriptions defined, exiting...'
        return
      end

      Artery.start do
        tries = 0
        begin
          Artery.subscriptions.each do |subscription|
            subscription.synchronize!

            Artery.logger.debug "Subscribing on '#{subscription.uri}'"
            Artery.subscribe subscription.uri.to_route, queue: "#{Artery.service_name}.worker" do |data, reply, from|
              begin
                subscription.handle(data, reply, from)
              rescue Exception => e
                Artery.handle_error Error.new("Error in subscription handling: #{e.inspect}\n#{e.backtrace.join("\n")}")
              end
            end
          end
        rescue Exception => e
          tries += 1

          Artery.handle_error Error.new("WORKER ERROR: #{e.inspect}: #{e.backtrace.join("\n")}")
          retry if tries <= 5

          Artery.handle_error Error.new('Worker failed 5 times and exited.')
        end
      end
    end
  end
end
