class CreateApplicationAnswers < ActiveRecord::Migration[8.1]
  def change
    create_table :application_answers do |t|
      t.references :membership_application, null: false, foreign_key: true
      t.references :application_form_question, null: false, foreign_key: true
      t.text :value

      t.timestamps
    end

    add_index :application_answers,
              %i[membership_application_id application_form_question_id],
              unique: true,
              name: 'idx_answers_application_question'
  end
end
