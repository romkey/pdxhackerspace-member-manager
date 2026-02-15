class AddServiceAccountToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :service_account, :boolean, default: false, null: false
  end
end
