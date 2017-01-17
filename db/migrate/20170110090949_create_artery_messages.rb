class CreateArteryMessages < ActiveRecord::Migration[5.0]
  def change
    create_table :artery_messages do |t|
      t.string    :version

      t.string    :model,      null:  false
      t.string    :action,     null:  false

      t.text      :data,       null:  false

      t.timestamp :created_at, limit: 6
    end
  end
end
