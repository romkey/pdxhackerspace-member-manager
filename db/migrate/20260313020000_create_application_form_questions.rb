class CreateApplicationFormQuestions < ActiveRecord::Migration[8.1]
  def change
    create_table :application_form_questions do |t|
      t.references :application_form_page, null: false, foreign_key: true
      t.text :label, null: false
      t.string :field_type, null: false, default: 'text'
      t.boolean :required, default: false, null: false
      t.integer :position, default: 0, null: false
      t.text :options_json
      t.text :help_text

      t.timestamps
    end

    add_index :application_form_questions, %i[application_form_page_id position],
              name: 'idx_form_questions_page_position'
  end
end
