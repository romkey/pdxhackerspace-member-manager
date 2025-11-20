class CreateApplicationGroupsUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :application_groups_users, id: false do |t|
      t.references :application_group, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
    
    add_index :application_groups_users, [:application_group_id, :user_id], unique: true, name: "index_app_groups_users_on_group_and_user"
  end
end
