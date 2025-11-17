class UpdateNullRfidToEmptyArray < ActiveRecord::Migration[7.1]
  def up
    # Update NULL rfid values to empty arrays
    execute <<-SQL
      UPDATE users SET rfid = '{}' WHERE rfid IS NULL;
    SQL
  end

  def down
    # This migration is not reversible in a meaningful way
    # NULL and empty array are effectively the same for our purposes
  end
end
