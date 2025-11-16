class CreateAccessLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :access_logs do |t|
      t.references :user, null: true, foreign_key: true
      t.string :location
      t.string :action
      t.text :raw_text
      t.datetime :logged_at

      t.timestamps
    end
    
    add_index :access_logs, :logged_at
  end
end
