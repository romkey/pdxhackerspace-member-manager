class UpdateMembershipStatusToEnumAndAddActiveToUsers < ActiveRecord::Migration[7.1]
  def up
    # Change default to "unknown"
    change_column_default :users, :membership_status, "unknown"
    
    # Update existing NULL values to "unknown"
    execute "UPDATE users SET membership_status = 'unknown' WHERE membership_status IS NULL"
    
    # Add active boolean column with default false
    add_column :users, :active, :boolean, default: false, null: false
    
    # Set active based on current membership_status
    # If membership_status was "active", set active to true
    execute "UPDATE users SET active = true WHERE membership_status = 'active'"
    
    # Update membership_status values to new enum values
    # Map old values to new ones
    execute "UPDATE users SET membership_status = 'unknown' WHERE membership_status NOT IN ('coworking', 'basic', 'guest', 'banned', 'deceased', 'unknown')"
  end
  
  def down
    # Revert active to membership_status
    execute "UPDATE users SET membership_status = 'active' WHERE active = true"
    execute "UPDATE users SET membership_status = 'inactive' WHERE active = false"
    
    remove_column :users, :active
    change_column_default :users, :membership_status, "inactive"
  end
end
