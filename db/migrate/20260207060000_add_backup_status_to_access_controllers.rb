class AddBackupStatusToAccessControllers < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:access_controllers, :backup_status)
      add_column :access_controllers, :backup_status, :string, default: 'unknown'
    end
    unless column_exists?(:access_controllers, :last_backup_at)
      add_column :access_controllers, :last_backup_at, :datetime
    end
  end
end
