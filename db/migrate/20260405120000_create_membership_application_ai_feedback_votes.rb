# frozen_string_literal: true

class CreateMembershipApplicationAiFeedbackVotes < ActiveRecord::Migration[8.1]
  def change
    create_table :membership_application_ai_feedback_votes do |t|
      t.references :membership_application, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true, index: false
      t.string :stance, null: false
      t.text :reason

      t.timestamps
    end

    add_index :membership_application_ai_feedback_votes,
              %i[membership_application_id user_id],
              unique: true,
              name: 'idx_ma_ai_fb_votes_app_user'
  end
end
