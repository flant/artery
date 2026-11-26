# frozen_string_literal: true

namespace :artery do
  # Rails initializes rake tasks without eager loading; the permissions need every model and declaration,
  # also those of engines and gems.
  task :eager_load do
    config = Rails.application.config
    config.rake_eager_load = true if config.respond_to?(:rake_eager_load=)
  end

  desc 'Print the nats.conf user entry with the subjects this service needs, ' \
       'optionally naming the variable of its password hash'
  task :permissions, [:password_variable] => %i[eager_load environment] do |_task, args|
    # Rails before 6.1, or an application initialized before this task, still has to be loaded.
    unless Rails.application.config.eager_load
      ActiveSupport.run_load_hooks(:before_eager_load, Rails.application)
      Zeitwerk::Loader.eager_load_all if defined?(Zeitwerk::Loader)
      Rails.application.config.eager_load_namespaces.each(&:eager_load!)
    end

    puts Artery::Permissions.new.to_nats_user(password_variable: args[:password_variable])
  end
end
