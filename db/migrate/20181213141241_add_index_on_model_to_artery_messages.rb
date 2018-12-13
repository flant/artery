class AddIndexOnModelToArteryMessages < ActiveRecord::Migration[5.0]
  def change
    add_index :artery_messages, :model
  end
end
