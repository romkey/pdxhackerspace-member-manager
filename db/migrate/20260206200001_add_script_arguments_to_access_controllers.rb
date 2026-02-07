class AddScriptArgumentsToAccessControllers < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:access_controllers, :script_arguments)
      add_column :access_controllers, :script_arguments, :string
    end
  end
end
