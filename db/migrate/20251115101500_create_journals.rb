class CreateJournals < ActiveRecord::Migration[7.1]
  def change
    create_table :journals do |t|
      t.references :user, null: false, foreign_key: true # target user whose record changed
      t.references :actor_user, null: true, foreign_key: { to_table: :users } # who made the change (nullable for system)
      t.string :action, null: false # e.g., created, updated, deactivated, reactivated
      t.jsonb :changes_json, null: false, default: {} # detailed old/new per attribute
      t.datetime :changed_at, null: false

      t.timestamps
    end

    add_index :journals, :changed_at
  end
end

