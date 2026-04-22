class MessageTrashCleanupJob < ApplicationJob
  queue_as :default

  def perform
    cutoff = Message::TRASH_RETENTION.ago
    Message.where.not(deleted_by_sender_at: nil)
           .where.not(deleted_by_recipient_at: nil)
           .where(deleted_by_sender_at: ...cutoff)
           .where(deleted_by_recipient_at: ...cutoff)
           .find_each(&:destroy)
  end
end
