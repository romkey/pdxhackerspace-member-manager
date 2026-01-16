class AddAccessControllerTypeToAccessControllers < ActiveRecord::Migration[7.1]
  def change
    add_reference :access_controllers, :access_controller_type, null: true, foreign_key: true
  end
end
