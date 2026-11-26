# frozen_string_literal: true

namespace :artery do
  desc 'Print the nats.conf user entry with the subjects this service needs, ' \
       'optionally naming the variable of its password hash'
  task :permissions, [:password_variable] => :environment do |_task, args|
    Rails.application.eager_load!

    puts Artery::Permissions.new.to_nats_user(password_variable: args[:password_variable])
  end
end
