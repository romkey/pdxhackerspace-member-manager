# frozen_string_literal: true

class CreateMembershipApplicationTourFeedbacksAndAcceptanceVotes < ActiveRecord::Migration[8.1]
  def change
    create_table :membership_application_tour_feedbacks do |t|
      t.references :membership_application, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true
      t.text :attitude
      t.text :impressions
      t.text :engagement
      t.text :fit_feeling

      t.timestamps
    end

    add_index :membership_application_tour_feedbacks,
              %i[membership_application_id user_id],
              unique: true,
              name: 'idx_ma_tour_feedbacks_app_user'

    create_table :membership_application_acceptance_votes do |t|
      t.references :membership_application, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true
      t.string :decision, null: false

      t.timestamps
    end

    add_index :membership_application_acceptance_votes,
              %i[membership_application_id user_id],
              unique: true,
              name: 'idx_ma_acceptance_votes_app_user'
  end
end
