# frozen_string_literal: true

class AddAiFeedbackToMembershipApplications < ActiveRecord::Migration[8.1]
  def change
    change_table :membership_applications, bulk: true do |t|
      t.integer :ai_feedback_score
      t.text :ai_feedback_score_rationale
      t.string :ai_feedback_recommendation
      t.jsonb :ai_feedback_questions, default: [], null: false
      t.boolean :ai_feedback_garbage, default: false, null: false
      t.text :ai_feedback_garbage_reason
      t.datetime :ai_feedback_processed_at
      t.text :ai_feedback_last_error
    end

    add_index :membership_applications, :ai_feedback_processed_at
  end
end
