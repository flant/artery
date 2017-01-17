class CreateArteryLastModelUpdates < ActiveRecord::Migration[5.0]
  def change
    create_table :artery_last_model_updates do |t|
      t.string :service, null: false
      t.string :model,   null: false

      t.timestamp :last_message_at, limit: 6, null: false
    end
  end
end
