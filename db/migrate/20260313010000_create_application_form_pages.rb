class CreateApplicationFormPages < ActiveRecord::Migration[8.1]
  def change
    create_table :application_form_pages do |t|
      t.string :title, null: false
      t.text :description
      t.integer :position, default: 0, null: false

      t.timestamps
    end

    add_index :application_form_pages, :position
  end
end
