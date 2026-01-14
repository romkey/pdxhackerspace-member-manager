class CreateEmailTemplates < ActiveRecord::Migration[7.1]
  def change
    create_table :email_templates do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.string :description
      t.string :subject, null: false
      t.text :body_html, null: false
      t.text :body_text, null: false
      t.boolean :enabled, default: true, null: false

      t.timestamps
    end

    add_index :email_templates, :key, unique: true
  end
end
