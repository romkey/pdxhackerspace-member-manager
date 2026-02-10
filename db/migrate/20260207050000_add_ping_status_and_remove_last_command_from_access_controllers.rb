class AddPingStatusAndRemoveLastCommandFromAccessControllers < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:access_controllers, :ping_status)
      add_column :access_controllers, :ping_status, :string, default: 'unknown'
    end
    unless column_exists?(:access_controllers, :last_ping_at)
      add_column :access_controllers, :last_ping_at, :datetime
    end

    remove_column :access_controllers, :last_command, :string if column_exists?(:access_controllers, :last_command)
    remove_column :access_controllers, :last_command_at, :datetime if column_exists?(:access_controllers, :last_command_at)
    remove_column :access_controllers, :last_command_status, :string if column_exists?(:access_controllers, :last_command_status)
    remove_column :access_controllers, :last_command_output, :text if column_exists?(:access_controllers, :last_command_output)
  end
end
