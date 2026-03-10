class AddLoginLinkExpiryToMembershipSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :membership_settings, :login_link_expiry_days, :integer, default: 30, null: false
  end
end
