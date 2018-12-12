class AddLatestIndexToArterySubscriptionInfos < ActiveRecord::Migration[5.0]
  def change
    add_column :artery_subscription_infos, :latest_index, :integer, unsigned: true
  end
end
