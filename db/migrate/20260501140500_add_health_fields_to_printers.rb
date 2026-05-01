class AddHealthFieldsToPrinters < ActiveRecord::Migration[8.1]
  def change
    change_table :printers, bulk: true do |t|
      t.string :health_status, default: 'unknown', null: false
      t.datetime :last_health_check_at
      t.string :last_health_error

      t.index :health_status
    end
  end
end
