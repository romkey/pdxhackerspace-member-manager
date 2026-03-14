class UpdateLoginLinkExpirySettings < ActiveRecord::Migration[8.1]
  def up
    rename_column :membership_settings, :login_link_expiry_days, :login_link_expiry_hours
    change_column_default :membership_settings, :login_link_expiry_hours, 180

    add_column :membership_settings, :admin_login_link_expiry_minutes, :integer, default: 15, null: false

    # Convert existing values from days to hours
    execute "UPDATE membership_settings SET login_link_expiry_hours = login_link_expiry_hours * 24"
  end

  def down
    # Convert hours back to days
    execute "UPDATE membership_settings SET login_link_expiry_hours = login_link_expiry_hours / 24"

    remove_column :membership_settings, :admin_login_link_expiry_minutes
    rename_column :membership_settings, :login_link_expiry_hours, :login_link_expiry_days
    change_column_default :membership_settings, :login_link_expiry_days, 30
  end
end
