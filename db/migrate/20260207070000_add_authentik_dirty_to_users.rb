class AddAuthentikDirtyToUsers < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:users, :authentik_dirty)
      add_column :users, :authentik_dirty, :boolean, null: false, default: false
      add_index :users, :authentik_dirty
    end
  end
end
