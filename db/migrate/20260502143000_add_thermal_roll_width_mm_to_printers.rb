class AddThermalRollWidthMmToPrinters < ActiveRecord::Migration[8.1]
  def change
    add_column :printers, :thermal_roll_width_mm, :integer
  end
end
