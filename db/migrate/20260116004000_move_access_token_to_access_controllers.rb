class MoveAccessTokenToAccessControllers < ActiveRecord::Migration[7.1]
  def up
    add_column :access_controllers, :access_token, :string

    AccessController.reset_column_information
    AccessControllerType.reset_column_information

    AccessController.includes(:access_controller_type).find_each do |controller|
      next if controller.access_token.present?

      token = controller.access_controller_type&.access_token
      controller.update_column(:access_token, token) if token.present?
    end

    remove_column :access_controller_types, :access_token, :string
  end

  def down
    add_column :access_controller_types, :access_token, :string

    AccessControllerType.reset_column_information
    AccessController.reset_column_information

    AccessController.includes(:access_controller_type).find_each do |controller|
      next if controller.access_token.blank?

      type = controller.access_controller_type
      next unless type && type.access_token.blank?

      type.update_column(:access_token, controller.access_token)
    end

    remove_column :access_controllers, :access_token, :string
  end
end
