class CreateRfidReaders < ActiveRecord::Migration[7.1]
  def change
    create_table :rfid_readers do |t|
      t.string :name, null: false
      t.text :note
      t.string :key, null: false, limit: 32

      t.timestamps
    end
    add_index :rfid_readers, :key, unique: true
  end
end
