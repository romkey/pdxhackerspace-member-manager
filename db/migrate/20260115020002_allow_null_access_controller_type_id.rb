class AllowNullAccessControllerTypeId < ActiveRecord::Migration[7.1]
  def change
    change_column_null :access_controllers, :access_controller_type_id, true
  end
end
