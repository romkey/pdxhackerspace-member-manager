class ChangeRfidToArrayInUsers < ActiveRecord::Migration[7.1]
  def up
    # Change rfid from text to text array using USING clause
    execute <<-SQL
      ALTER TABLE users 
      ALTER COLUMN rfid TYPE text[] 
      USING CASE 
        WHEN rfid IS NULL THEN '{}'::text[]
        WHEN rfid = '' THEN '{}'::text[]
        ELSE ARRAY[rfid]::text[]
      END;
    SQL
    
    # Set default
    change_column_default :users, :rfid, []
  end

  def down
    # Convert array back to text (take first element if array has values)
    execute <<-SQL
      UPDATE users 
      SET rfid = CASE 
        WHEN rfid IS NULL OR array_length(rfid, 1) IS NULL THEN NULL
        ELSE rfid[1]
      END;
    SQL
    
    change_column :users, :rfid, :text
  end
end
