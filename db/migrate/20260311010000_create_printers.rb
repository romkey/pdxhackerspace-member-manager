class CreatePrinters < ActiveRecord::Migration[8.1]
  def change
    create_table :printers do |t|
      t.string :name, null: false
      t.string :cups_printer_name, null: false
      t.string :description
      t.boolean :default_printer, default: false, null: false
      t.integer :position, default: 0, null: false

      t.timestamps
    end

    add_index :printers, :name, unique: true
    add_index :printers, :cups_printer_name, unique: true
  end
end
