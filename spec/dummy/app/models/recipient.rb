class Recipient < ApplicationRecord
  extend Artery::Model

  artery_model

  artery_watch_model service: :test, model: :source, synchronize: true do |on|
    on.create do |data|
      create! data.slice('uuid', 'name')
    end
  end
end
