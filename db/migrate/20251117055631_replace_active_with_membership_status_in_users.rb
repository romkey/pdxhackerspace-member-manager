class ReplaceActiveWithMembershipStatusInUsers < ActiveRecord::Migration[7.1]
  def up
    # Add membership_status column
    add_column :users, :membership_status, :string, default: "inactive"
    
    # Migrate existing data: active = true -> "active", active = false -> "inactive"
    execute <<-SQL
      UPDATE users 
      SET membership_status = CASE 
        WHEN active = true THEN 'active'
        ELSE 'inactive'
      END;
    SQL
    
    # Remove the active column
    remove_column :users, :active
  end

  def down
    # Add active column back
    add_column :users, :active, :boolean, default: true, null: false
    
    # Migrate data back: "active" -> true, everything else -> false
    execute <<-SQL
      UPDATE users 
      SET active = CASE 
        WHEN membership_status = 'active' THEN true
        ELSE false
      END;
    SQL
    
    # Remove membership_status
    remove_column :users, :membership_status
  end
end
