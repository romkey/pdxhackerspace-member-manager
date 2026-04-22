module MessagesHelper
  def viewer_deletion_time(message, viewer)
    if message.sender_id == viewer.id && message.deleted_by_sender_at.present?
      message.deleted_by_sender_at
    elsif message.recipient_id == viewer.id && message.deleted_by_recipient_at.present?
      message.deleted_by_recipient_at
    end
  end
end
