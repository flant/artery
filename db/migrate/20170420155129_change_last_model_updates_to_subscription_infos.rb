class ChangeLastModelUpdatesToSubscriptionInfos < ActiveRecord::Migration[5.0]
  def change
    rename_table :artery_last_model_updates, :artery_subscription_infos
  end
end
