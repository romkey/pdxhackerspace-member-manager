class CreateSlackUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :slack_users do |t|
      t.string :slack_id, null: false
      t.string :team_id
      t.string :username
      t.string :real_name
      t.string :display_name
      t.string :email
      t.string :title
      t.string :phone
      t.string :tz
      t.boolean :is_admin, null: false, default: false
      t.boolean :is_owner, null: false, default: false
      t.boolean :is_bot, null: false, default: false
      t.boolean :deleted, null: false, default: false
      t.jsonb :raw_attributes, null: false, default: {}
      t.datetime :last_synced_at

      t.timestamps
    end

    add_index :slack_users, :slack_id, unique: true
    add_index :slack_users, :email, unique: true, where: "email IS NOT NULL"
    add_index :slack_users, :raw_attributes, using: :gin
  end
end
