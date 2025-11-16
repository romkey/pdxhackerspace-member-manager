class AddUserToSheetEntries < ActiveRecord::Migration[7.1]
  def change
    add_reference :sheet_entries, :user, null: true, foreign_key: true
  end
end
