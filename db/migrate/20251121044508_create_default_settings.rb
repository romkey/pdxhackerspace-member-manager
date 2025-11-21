class CreateDefaultSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :default_settings do |t|
      t.string :site_prefix, default: "ctrlh", null: false
      t.string :app_prefix, null: false
      t.string :members_prefix, null: false
      t.string :active_members_group, null: false
      t.string :admins_group, null: false

      t.timestamps
    end
  end
end
