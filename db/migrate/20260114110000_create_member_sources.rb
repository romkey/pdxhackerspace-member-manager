class CreateMemberSources < ActiveRecord::Migration[7.1]
  def change
    create_table :member_sources do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.boolean :enabled, default: true, null: false
      t.integer :display_order, default: 0

      # Configuration
      t.boolean :api_configured, default: false

      # Statistics
      t.integer :entry_count, default: 0
      t.integer :linked_count, default: 0
      t.integer :unlinked_count, default: 0

      # Sync tracking
      t.datetime :last_sync_at

      # Admin notes
      t.text :notes

      t.timestamps
    end

    add_index :member_sources, :key, unique: true
    add_index :member_sources, :enabled
    add_index :member_sources, :display_order
  end
end
