class ChangeLastModelUpdatesToSubscriptionInfos < ActiveRecord::Migration[5.0]
  def up
    rename_table :artery_last_model_updates, :artery_subscription_infos

    change_column :artery_subscription_infos, :last_message_at, :timestamp, limit: 6, null: true
    add_column :artery_subscription_infos, :synchronization_in_progress, :boolean, default: false
    add_column :artery_subscription_infos, :synchronization_page, :integer
  end

  def down
    remove_column :artery_subscription_infos, :synchronization_in_progress
    remove_column :artery_subscription_infos, :synchronization_page
    change_column :artery_subscription_infos, :last_message_at, :timestamp, limit: 6, null: false

    rename_table :artery_subscription_infos, :artery_last_model_updates
  end
end
