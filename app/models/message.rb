class Message < ApplicationRecord
  TRASH_RETENTION = 30.days
  FOLDERS = %i[unread read sent all trash].freeze

  belongs_to :sender, class_name: 'User'
  belongs_to :recipient, class_name: 'User'

  validates :subject, presence: true
  validates :body, presence: true

  scope :newest_first, -> { order(created_at: :desc) }
  scope :unread, -> { where(read_at: nil) }
  scope :for_user, ->(user) { where(recipient: user) }

  scope :not_deleted_by_sender,    -> { where(deleted_by_sender_at: nil) }
  scope :not_deleted_by_recipient, -> { where(deleted_by_recipient_at: nil) }

  scope :visible_to, lambda { |user|
    where(
      '(recipient_id = :id AND deleted_by_recipient_at IS NULL) OR ' \
      '(sender_id = :id AND deleted_by_sender_at IS NULL)',
      id: user.id
    )
  }

  scope :trash_for, lambda { |user, cutoff: TRASH_RETENTION.ago|
    where(
      '(recipient_id = :id AND deleted_by_recipient_at > :t) OR ' \
      '(sender_id = :id AND deleted_by_sender_at > :t)',
      id: user.id, t: cutoff
    )
  }

  # Returns a relation scoped to the user and a named folder.
  # Valid folders: :unread, :read, :sent, :all, :trash
  def self.folder(user, folder)
    case folder.to_sym
    when :unread then where(recipient: user, deleted_by_recipient_at: nil, read_at: nil)
    when :read   then where(recipient: user, deleted_by_recipient_at: nil).where.not(read_at: nil)
    when :sent   then where(sender: user, deleted_by_sender_at: nil)
    when :all    then visible_to(user)
    when :trash  then trash_for(user)
    else none
    end
  end

  def unread?
    read_at.nil?
  end

  def read!
    update!(read_at: Time.current) if read_at.nil?
  end

  def unread!
    update!(read_at: nil) unless read_at.nil?
  end

  # Soft-deletes the message for the given user (the user's side only).
  # If user is both sender and recipient (self-message), both sides are marked.
  def delete_for(user)
    updates = {}
    now = Time.current
    updates[:deleted_by_sender_at]    = now if sender_id    == user.id && deleted_by_sender_at.nil?
    updates[:deleted_by_recipient_at] = now if recipient_id == user.id && deleted_by_recipient_at.nil?
    return false if updates.empty?

    update!(updates)
  end

  # Restores the message from the user's trash (only while within retention window).
  def restore_for(user)
    updates = {}
    updates[:deleted_by_sender_at]    = nil if can_restore?(user, :sender)
    updates[:deleted_by_recipient_at] = nil if can_restore?(user, :recipient)
    return false if updates.empty?

    update!(updates)
  end

  # True if the user can currently see this message in one of their folders
  # (inbox / sent / all). Does not include trash.
  def visible_to?(user)
    (recipient_id == user.id && deleted_by_recipient_at.nil?) ||
      (sender_id == user.id && deleted_by_sender_at.nil?)
  end

  # True if the message is currently in the user's trash window.
  def in_trash_for?(user, cutoff: TRASH_RETENTION.ago)
    (recipient_id == user.id && deleted_by_recipient_at.present? && deleted_by_recipient_at > cutoff) ||
      (sender_id == user.id && deleted_by_sender_at.present? && deleted_by_sender_at > cutoff)
  end

  # True if the user has soft-deleted the message from their side.
  def deleted_by?(user)
    (sender_id == user.id && deleted_by_sender_at.present?) ||
      (recipient_id == user.id && deleted_by_recipient_at.present?)
  end

  private

  def can_restore?(user, role, cutoff: TRASH_RETENTION.ago)
    case role
    when :sender
      sender_id == user.id && deleted_by_sender_at.present? && deleted_by_sender_at > cutoff
    when :recipient
      recipient_id == user.id && deleted_by_recipient_at.present? && deleted_by_recipient_at > cutoff
    end
  end
end
