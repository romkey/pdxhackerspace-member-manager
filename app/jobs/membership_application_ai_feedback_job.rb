# frozen_string_literal: true

class MembershipApplicationAiFeedbackJob < ApplicationJob
  queue_as :default

  def perform(membership_application_id)
    application = MembershipApplication.find_by(id: membership_application_id)
    return if application.nil?

    MembershipApplications::ProcessAiFeedback.call(application: application)
  end
end
