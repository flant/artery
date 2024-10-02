FactoryBot.define do
  factory :recipient do
    uuid { Faker::Internet.uuid }
    name { Faker::Name.name }
  end
end
