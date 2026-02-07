class AddScriptArgumentsToAccessControllers < ActiveRecord::Migration[8.0]
  def change
    add_column :access_controllers, :script_arguments, :string
  end
end
