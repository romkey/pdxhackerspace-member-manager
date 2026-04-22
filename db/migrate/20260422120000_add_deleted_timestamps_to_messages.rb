class AddDeletedTimestampsToMessages < ActiveRecord::Migration[8.0]
  def change
    change_table :messages, bulk: true do |t|
      t.datetime :deleted_by_sender_at
      t.datetime :deleted_by_recipient_at
    end

    add_index :messages, %i[sender_id deleted_by_sender_at]
    add_index :messages, %i[recipient_id deleted_by_recipient_at]
  end
end
