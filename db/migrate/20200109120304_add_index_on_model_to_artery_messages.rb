class AddIndexOnModelToArteryMessages < ActiveRecord::Migration[5.2]
  def up
    add_index :artery_messages, :model unless index_exists?(:artery_messages, :model)
  end

  def down
    remove_index :artery_messages, :model
  end
end
