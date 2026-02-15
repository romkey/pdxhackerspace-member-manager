class AddSyncInactiveMembersToDefaultSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :default_settings, :sync_inactive_members, :boolean, default: false, null: false
  end
end
