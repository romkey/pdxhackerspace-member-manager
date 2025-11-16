class CreateUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :users do |t|
      t.string :authentik_id, null: false
      t.string :email, null: false
      t.string :full_name
      t.boolean :active, null: false, default: true
      t.datetime :last_synced_at

      t.timestamps
    end
    add_index :users, :authentik_id, unique: true
    add_index :users, :email, unique: true
  end
end
