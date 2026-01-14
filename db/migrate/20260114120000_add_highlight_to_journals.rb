class AddHighlightToJournals < ActiveRecord::Migration[7.1]
  def change
    add_column :journals, :highlight, :boolean, default: false, null: false
    add_index :journals, :highlight
  end
end
