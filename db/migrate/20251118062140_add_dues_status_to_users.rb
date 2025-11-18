class AddDuesStatusToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :dues_status, :string, default: "unknown"
  end
end
