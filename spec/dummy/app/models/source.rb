class Source < ApplicationRecord
  extend Artery::Model

  artery_model source: true

  artery_representation do
    attrs.slice('uuid', 'name')
  end
end
