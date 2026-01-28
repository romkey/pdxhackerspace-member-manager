# SPDX-FileCopyrightText: 2026 John Romkey
#
# SPDX-License-Identifier: CC0-1.0

class CreateAuthentikUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :authentik_users do |t|
      t.string :authentik_id, null: false
      t.string :username
      t.string :email
      t.string :full_name
      t.boolean :is_active, default: true, null: false
      t.boolean :is_superuser, default: false, null: false
      t.jsonb :raw_attributes, default: {}, null: false
      t.datetime :last_synced_at
      t.references :user, foreign_key: true, index: true

      t.timestamps
    end

    add_index :authentik_users, :authentik_id, unique: true
    add_index :authentik_users, :email
    add_index :authentik_users, :raw_attributes, using: :gin
  end
end
