class CreateRecipients < ActiveRecord::Migration[7.2]
  def change
    create_table :recipients do |t|
      t.string :uuid
      t.string :name

      t.timestamps
    end
  end
end
