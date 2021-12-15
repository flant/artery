class RemoveLastMessageAtFromArterySubscriptionInfos < ActiveRecord::Migration[5.2]
  def up
    remove_column :artery_subscription_infos, :last_message_at if column_exists?(:artery_subscription_infos, :last_message_at)
  end

  def down
    add_column :artery_subscription_infos, :last_message_at, :timestamp
  end
end
