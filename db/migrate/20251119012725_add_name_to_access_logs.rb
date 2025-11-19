class AddNameToAccessLogs < ActiveRecord::Migration[7.1]
  def change
    add_column :access_logs, :name, :string
    add_index :access_logs, :name
    add_index :access_logs, :location
  end
end
