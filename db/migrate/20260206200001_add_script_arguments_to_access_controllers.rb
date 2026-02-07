class AddScriptArgumentsToAccessControllers < ActiveRecord::Migration[7.1]
  def change
    add_column :access_controllers, :script_arguments, :string
  end
end
