class RemoveLastSyncMessageFromAccessControllers < ActiveRecord::Migration[7.1]
  def change
    remove_column :access_controllers, :last_sync_message, :text
  end
end
