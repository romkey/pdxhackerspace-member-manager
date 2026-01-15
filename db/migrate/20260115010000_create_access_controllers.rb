class CreateAccessControllers < ActiveRecord::Migration[7.1]
  def change
    create_table :access_controllers do |t|
      t.string :name, null: false
      t.string :hostname, null: false
      t.text :description
      t.boolean :enabled, default: true, null: false
      t.datetime :last_sync_at
      t.string :sync_status, default: 'unknown', null: false
      t.text :last_sync_message
      t.integer :display_order, default: 0

      t.timestamps
    end

    add_index :access_controllers, :name, unique: true
    add_index :access_controllers, :hostname
    add_index :access_controllers, :enabled
  end
end
