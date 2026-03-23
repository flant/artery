# frozen_string_literal: true

class CreateArteryModelInfos < ActiveRecord::Migration[5.2]
  def up
    create_table :artery_model_infos do |t|
      t.string :model, null: false
      t.bigint :latest_index, null: false, default: 0
    end

    add_index :artery_model_infos, :model, unique: true

    execute <<~SQL.squish
      INSERT INTO artery_model_infos (model, latest_index)
      SELECT model, COALESCE(MAX(id), 0)
      FROM artery_messages
      GROUP BY model
    SQL
  end

  def down
    drop_table :artery_model_infos
  end
end
