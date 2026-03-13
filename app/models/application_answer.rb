class ApplicationAnswer < ApplicationRecord
  belongs_to :membership_application
  belongs_to :application_form_question

  validates :application_form_question_id,
            uniqueness: { scope: :membership_application_id }
end
