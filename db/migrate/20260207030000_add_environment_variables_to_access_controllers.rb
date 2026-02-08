class AddEnvironmentVariablesToAccessControllers < ActiveRecord::Migration[7.1]
  def change
    add_column :access_controllers, :environment_variables, :text
  end
end
