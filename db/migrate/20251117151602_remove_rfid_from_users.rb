class RemoveRfidFromUsers < ActiveRecord::Migration[7.1]
  def up
    # Migrate existing RFID data to the new rfids table
    execute <<-SQL
      INSERT INTO rfids (user_id, rfid, created_at, updated_at)
      SELECT id, unnest(rfid), NOW(), NOW()
      FROM users
      WHERE rfid IS NOT NULL AND array_length(rfid, 1) > 0;
    SQL
    
    # Remove the rfid column
    remove_column :users, :rfid
  end

  def down
    # Add rfid column back as array
    add_column :users, :rfid, :text, array: true, default: []
    
    # Migrate data back (aggregate rfids per user)
    execute <<-SQL
      UPDATE users
      SET rfid = (
        SELECT ARRAY_AGG(rfid)
        FROM rfids
        WHERE rfids.user_id = users.id
      )
      WHERE EXISTS (SELECT 1 FROM rfids WHERE rfids.user_id = users.id);
    SQL
  end
end
