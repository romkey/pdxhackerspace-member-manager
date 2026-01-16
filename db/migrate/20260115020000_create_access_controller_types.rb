class CreateAccessControllerTypes < ActiveRecord::Migration[7.1]
  def change
    create_table :access_controller_types do |t|
      t.string :name, null: false
      t.string :script_path, null: false
      t.string :access_token
      t.boolean :enabled, default: true, null: false

      t.timestamps
    end

    add_index :access_controller_types, :name, unique: true
    add_index :access_controller_types, :enabled
  end
end
