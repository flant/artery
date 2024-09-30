# frozen_string_literal: true

FactoryBot.define do
  factory :source do
    uuid { Faker::Internet.uuid }
    name { Faker::Name.name }
  end
end
