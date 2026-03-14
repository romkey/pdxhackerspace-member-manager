class MakeJournalUserOptional < ActiveRecord::Migration[8.0]
  def change
    change_column_null :journals, :user_id, true
  end
end
