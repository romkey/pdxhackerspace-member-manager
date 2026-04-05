# frozen_string_literal: true

class ApplicationRejectedMailJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  discard_on ActiveRecord::RecordNotFound

  def perform(membership_application_id, admin_notes)
    app = MembershipApplication.find(membership_application_id)
    QueuedMail.enqueue_application_rejected(app, reason: admin_notes.presence)
  end
end
