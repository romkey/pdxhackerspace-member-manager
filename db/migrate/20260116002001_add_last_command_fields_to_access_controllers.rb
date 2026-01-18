class AddLastCommandFieldsToAccessControllers < ActiveRecord::Migration[7.1]
  def change
    add_column :access_controllers, :last_command, :string
    add_column :access_controllers, :last_command_at, :datetime
    add_column :access_controllers, :last_command_status, :string
    add_column :access_controllers, :last_command_output, :text
  end
end
