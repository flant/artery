# frozen_string_literal: true

namespace :artery do
  desc 'Print the nats.conf user entry with the subjects this service needs, ' \
       'optionally naming the variable of its password hash and the user'
  task :permissions, %i[password_variable user] => :environment do |_task, args|
    Artery::Permissions.load_application
    puts Artery::Permissions.new.to_nats_user(password_variable: args[:password_variable], user: args[:user])
  end
end
