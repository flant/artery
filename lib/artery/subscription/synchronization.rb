# frozen_string_literal: true

module Artery
  class Subscription
    module Synchronization
      extend ActiveSupport::Concern

      ALIVE_EDGE = 2.minutes
      HEARTBEAT_INTERVAL = 30.seconds

      def synchronize?
        options[:synchronize]
      end

      def synchronize_updates?
        options[:synchronize_updates]
      end

      def synchronization_scope
        options[:synchronize].is_a?(Hash) ? options[:synchronize][:scope] : nil
      end

      def synchronization_per_page
        options[:synchronize].is_a?(Hash) ? options[:synchronize][:per_page] : nil
      end

      def synchronize_updates_scope
        (options[:synchronize_updates].is_a?(Hash) && options[:synchronize_updates][:scope]) || synchronization_scope
      end

      def synchronize_updates_per_page
        (options[:synchronize_updates].is_a?(Hash) && options[:synchronize_updates][:per_page]) || synchronization_per_page
      end

      def synchronize_updates_autoenrich?
        options[:synchronize_updates].is_a?(Hash) ? options[:synchronize_updates][:autoenrich] : false
      end

      def synchronization_in_progress?
        info.synchronization_in_progress? && synchronization_alive?
      end

      def synchronization_alive?
        info.synchronization_heartbeat.blank? || (Time.zone.now - info.synchronization_heartbeat) < ALIVE_EDGE
      end

      def synchronization_in_progress!(val = true)
        if val
          Artery.synchronizing_subscriptions << self
          run_synchronization_heartbeat

          info.update! synchronization_in_progress: true, synchronization_heartbeat: Time.zone.now
        else
          Artery.synchronizing_subscriptions.delete self
          stop_synchronization_heartbeat

          info.update! synchronization_in_progress: false, synchronization_heartbeat: nil
        end
      end

      def synchronization_transaction(&blk)
        return unless blk
        return info.synchronization_transaction(&blk) if info.respond_to?(:synchronization_transaction)

        blk.call
      end

      def synchronization_page_update!(page)
        info.update! synchronization_page: page
      end

      def synchronize!
        return if uri.service == Artery.service_name || synchronization_in_progress?

        if !new? && synchronize_updates?
          receive_updates
        elsif new? && synchronize?
          receive_all
        end
      end

      def receive_all
        synchronization_in_progress! unless synchronization_in_progress?

        while receive_all_once == :continue; end
      end

      def receive_updates
        synchronization_in_progress!

        while receive_updates_once == :continue; end
      end

      private

      def run_synchronization_heartbeat
        return if @heartbeat_thread

        @heartbeat_thread = Thread.new do
          while @heartbeat_thread
            sleep HEARTBEAT_INTERVAL

            info.update! synchronization_heartbeat: Time.zone.now
          end
        end
      end

      def stop_synchronization_heartbeat
        @heartbeat_thread&.exit
      end

      def receive_all_once # rubocop:disable Metrics/AbcSize
        should_continue = false
        all_uri = Routing.uri(service: uri.service, model: uri.model, plural: true, action: :get_all)

        page = info.synchronization_page ? info.synchronization_page + 1 : 0 if synchronization_per_page

        objects = nil

        all_data = {
          representation: representation_name,
          scope: synchronization_scope,
          page: page,
          per_page: synchronization_per_page
        }

        Artery.request all_uri.to_route, all_data do |on|
          on.success do |data|
            Artery.logger.debug "HEY-HEY, ALL OBJECTS: <#{all_uri.to_route}> #{[data].inspect}"

            objects = data[:objects].map(&:with_indifferent_access)

            synchronization_transaction { handler.call(:synchronization, objects, page) }

            if synchronization_per_page && objects.count.positive?
              synchronization_page_update!(page)
              Artery.logger.debug "PAGE #{page} RECEIVED, WILL CONTINUE..."
              should_continue = true
            else
              synchronization_page_update!(nil) if synchronization_per_page
              synchronization_in_progress!(false)
              update_info_by_message!(IncomingMessage.new(self, data, nil, all_uri.to_route))
            end
          rescue Exception => e
            synchronization_in_progress!(false)
            Artery.handle_error Error.new("Error in all objects request handling: #{e.inspect}",
                                          original_exception: e,
                                          request: {
                                            route: all_uri.to_route,
                                            data: all_data.to_json
                                          },
                                          response: data.to_json)
          end

          on.error do |e|
            synchronization_in_progress!(false)
            error = Error.new "Failed to get all objects #{uri.model} from #{uri.service} with scope='#{synchronization_scope}': "\
                              "#{e.message}", **e.artery_context
            Artery.handle_error error
          end
        end
        :continue if should_continue
      end

      def receive_updates_once # rubocop:disable Metrics/AbcSize
        should_continue = false
        updates_uri = Routing.uri(service: uri.service, model: uri.model, plural: true, action: :get_updates)
        updates_data = {
          after_index: latest_message_index
        }

        # Configurable autoenrich updates
        if synchronize_updates_autoenrich?
          # we must setup per_page as data is autoenriched and can be big
          updates_data.merge! representation: representation_name,
                              scope: synchronize_updates_scope,
                              per_page: synchronize_updates_per_page
        end

        Artery.request updates_uri.to_route, updates_data do |on|
          on.success do |data|
            Artery.logger.debug "HEY-HEY, LAST_UPDATES: <#{updates_uri.to_route}> #{[data].inspect}"

            updates = data[:updates].map(&:with_indifferent_access)
            synchronization_transaction do
              updates.sort_by { |u| u[:_index] }.each do |update|
                from = Routing.uri(service: uri.service, model: uri.model, action: update.delete(:action)).to_route
                handle(IncomingMessage.new(self, update, nil, from, from_updates: true))
              end

              update_info_by_message! IncomingMessage.new(self, data, nil, updates_uri.to_route)
            end

            if data[:_continue]
              Artery.logger.debug 'NOT ALL UPDATES RECEIVED, WILL CONTINUE...'
              should_continue = true
            else
              synchronization_in_progress!(false)
            end
          rescue Exception => e
            synchronization_in_progress!(false)
            Artery.handle_error Error.new("Error in updates request handling: #{e.inspect}",
                                          original_exception: e,
                                          request: {
                                            route: updates_uri.to_route,
                                            data: updates_data.to_json
                                          },
                                          response: data.to_json)
          end

          on.error do |e|
            synchronization_in_progress!(false)
            Artery.handle_error Error.new("Failed to get updates for #{uri.model} from #{uri.service}: #{e.message}", **e.artery_context)
          end
        end
        :continue if should_continue
      end
    end
  end
end
