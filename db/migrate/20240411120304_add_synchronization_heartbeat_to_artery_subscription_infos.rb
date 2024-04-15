class AddSynchronizationHeartbeatToArterySubscriptionInfos < ActiveRecord::Migration[5.2]
  def up
    return if column_exists?(:artery_subscription_infos, :synchronization_heartbeat)

    add_column :artery_subscription_infos, :synchronization_heartbeat, :timestamp, after: :synchronization_in_progress
  end

  def down
    remove_column :artery_subscription_infos, :synchronization_heartbeat
  end
end
