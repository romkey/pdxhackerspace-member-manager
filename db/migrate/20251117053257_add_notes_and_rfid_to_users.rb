class AddNotesAndRfidToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :notes, :text
    add_column :users, :rfid, :text, array: true, default: []
  end
end
