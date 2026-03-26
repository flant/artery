# frozen_string_literal: true

class AddLastPublishedIdToArteryModelInfos < ActiveRecord::Migration[5.2]
  def change
    add_column :artery_model_infos, :last_published_id, :bigint, null: false, default: 0
  end
end
