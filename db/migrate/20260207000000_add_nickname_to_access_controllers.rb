class AddNicknameToAccessControllers < ActiveRecord::Migration[7.1]
  def change
    add_column :access_controllers, :nickname, :string
  end
end
