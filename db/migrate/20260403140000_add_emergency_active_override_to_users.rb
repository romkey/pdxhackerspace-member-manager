class AddEmergencyActiveOverrideToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :emergency_active_override, :boolean, default: false, null: false
  end
end
