class QueuedMailDeliveryJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  discard_on ActiveRecord::RecordNotFound

  def perform(queued_mail_id)
    queued_mail = QueuedMail.find(queued_mail_id)
    return if queued_mail.sent_at.present?
    return unless queued_mail.approved?

    queued_mail.deliver_now!
  end
end
