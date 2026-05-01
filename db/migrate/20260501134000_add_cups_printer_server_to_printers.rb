class AddCupsPrinterServerToPrinters < ActiveRecord::Migration[8.1]
  def change
    add_column :printers, :cups_printer_server, :string, default: '', null: false

    remove_index :printers, :cups_printer_name
    add_index :printers, %i[cups_printer_server cups_printer_name], unique: true
  end
end
