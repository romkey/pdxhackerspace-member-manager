class UpdateMembershipStatusAndAddProfileVisibility < ActiveRecord::Migration[7.1]
  def up
    # Convert existing coworking and basic statuses to paying
    execute <<-SQL
      UPDATE users SET membership_status = 'paying' WHERE membership_status IN ('coworking', 'basic');
    SQL

    # Add profile_visibility column with default 'members'
    add_column :users, :profile_visibility, :string, default: 'members', null: false
  end

  def down
    remove_column :users, :profile_visibility

    # Note: Cannot restore original coworking/basic distinction
    execute <<-SQL
      UPDATE users SET membership_status = 'unknown' WHERE membership_status = 'paying';
    SQL
  end
end
