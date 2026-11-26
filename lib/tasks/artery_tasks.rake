# frozen_string_literal: true

namespace :artery do
  desc 'Print the nats.conf user entry with the subjects this service needs, ' \
       'optionally naming the variable of its password hash'
  task :permissions, [:password_variable] => :environment do |_task, args|
    # Rails initializes rake tasks without eager loading, unless config.rake_eager_load is set, and the flag
    # alone does not show whether an application initialized earlier was loaded. The permissions need every
    # model and declaration the worker loads, also those of engines and gems; loading again is a no-op.
    ActiveSupport.run_load_hooks(:before_eager_load, Rails.application) unless Rails.application.config.eager_load
    Zeitwerk::Loader.eager_load_all if defined?(Zeitwerk::Loader)
    Rails.application.config.eager_load_namespaces.each(&:eager_load!)

    puts Artery::Permissions.new.to_nats_user(password_variable: args[:password_variable])
  end
end
