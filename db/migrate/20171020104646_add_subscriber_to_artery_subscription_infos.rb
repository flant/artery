class AddSubscriberToArterySubscriptionInfos < ActiveRecord::Migration[5.0]
  def change
    add_column :artery_subscription_infos, :subscriber, :string, after: :id
  end
end
