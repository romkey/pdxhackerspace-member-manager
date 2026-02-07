class CreateAccessControllerLogs < ActiveRecord::Migration[7.1]
  def change
    unless table_exists?(:access_controller_logs)
      create_table :access_controller_logs do |t|
        t.references :access_controller, null: false, foreign_key: true
        t.string :action, null: false
        t.string :command_line
        t.text :output
        t.integer :exit_code
        t.string :status, null: false, default: 'running'

        t.timestamps
      end

      add_index :access_controller_logs, :created_at
      add_index :access_controller_logs, :action
      add_index :access_controller_logs, :status
    end
  end
end
