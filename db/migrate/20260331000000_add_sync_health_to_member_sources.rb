class AddSyncHealthToMemberSources < ActiveRecord::Migration[8.1]
  def change
    add_column :member_sources, :last_successful_sync_at, :datetime
    add_column :member_sources, :last_error_message, :text
    add_column :member_sources, :consecutive_error_count, :integer, default: 0, null: false
    add_column :member_sources, :sync_status, :string, default: 'unknown', null: false
  end
end
