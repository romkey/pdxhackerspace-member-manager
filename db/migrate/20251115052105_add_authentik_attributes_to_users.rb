class AddAuthentikAttributesToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :authentik_attributes, :jsonb, null: false, default: {}
    add_index :users, :authentik_attributes, using: :gin
  end
end
