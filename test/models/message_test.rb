require 'test_helper'

class MessageTest < ActiveSupport::TestCase
  setup do
    @sender = users(:one)
    @recipient = users(:two)
    @other = users(:three)
  end

  def create_message(attrs = {})
    Message.create!(
      {
        sender: @sender,
        recipient: @recipient,
        subject: 'Hello',
        body: 'Test'
      }.merge(attrs)
    )
  end

  # ─── Validations & basic lifecycle ───────────────────────────────

  test 'valid message saves successfully' do
    message = Message.new(sender: @sender, recipient: @recipient, subject: 'Hello', body: 'Test body')
    assert message.valid?
    assert message.save
  end

  test 'requires subject' do
    message = Message.new(sender: @sender, recipient: @recipient, subject: '', body: 'Test body')
    assert_not message.valid?
    assert_includes message.errors[:subject], "can't be blank"
  end

  test 'requires body' do
    message = Message.new(sender: @sender, recipient: @recipient, subject: 'Hello', body: '')
    assert_not message.valid?
    assert_includes message.errors[:body], "can't be blank"
  end

  test 'requires sender' do
    message = Message.new(recipient: @recipient, subject: 'Hello', body: 'Test body')
    assert_not message.valid?
    assert message.errors[:sender].any?
  end

  test 'requires recipient' do
    message = Message.new(sender: @sender, subject: 'Hello', body: 'Test body')
    assert_not message.valid?
    assert message.errors[:recipient].any?
  end

  test 'unread? returns true when read_at is nil' do
    message = create_message
    assert message.unread?
  end

  test 'unread? returns false after read!' do
    message = create_message
    message.read!
    assert_not message.unread?
    assert_not_nil message.read_at
  end

  test 'read! is idempotent' do
    message = create_message
    message.read!
    first_read_at = message.read_at
    message.read!
    assert_equal first_read_at, message.read_at
  end

  test 'unread! clears read_at' do
    message = create_message
    message.read!
    assert_not_nil message.read_at
    message.unread!
    assert_nil message.read_at
  end

  test 'unread! is idempotent when already unread' do
    message = create_message
    assert_nil message.read_at
    message.unread!
    assert_nil message.read_at
  end

  # ─── Existing scopes ─────────────────────────────────────────────

  test 'newest_first scope orders by created_at desc' do
    create_message(subject: 'Old')
    new_msg = create_message(subject: 'New')
    assert_equal new_msg, Message.newest_first.first
  end

  test 'unread scope returns only unread messages' do
    unread = create_message(subject: 'Unread')
    read_msg = create_message(subject: 'Read')
    read_msg.read!
    results = Message.unread
    assert_includes results, unread
    assert_not_includes results, read_msg
  end

  test 'for_user scope returns messages for the given recipient' do
    msg_for_two = create_message
    msg_for_one = Message.create!(sender: @recipient, recipient: @sender, subject: 'Other', body: 'Test')
    results = Message.for_user(@recipient)
    assert_includes results, msg_for_two
    assert_not_includes results, msg_for_one
  end

  test 'not_deleted_by_sender filters sender-deleted rows' do
    kept = create_message
    deleted = create_message
    deleted.update!(deleted_by_sender_at: Time.current)
    assert_includes Message.not_deleted_by_sender, kept
    assert_not_includes Message.not_deleted_by_sender, deleted
  end

  test 'not_deleted_by_recipient filters recipient-deleted rows' do
    kept = create_message
    deleted = create_message
    deleted.update!(deleted_by_recipient_at: Time.current)
    assert_includes Message.not_deleted_by_recipient, kept
    assert_not_includes Message.not_deleted_by_recipient, deleted
  end

  # ─── visible_to scope ─────────────────────────────────────────────

  test 'visible_to includes sender side when not sender-deleted' do
    message = create_message
    assert_includes Message.visible_to(@sender), message
    assert_includes Message.visible_to(@recipient), message
  end

  test 'visible_to excludes sender when sender soft-deleted' do
    message = create_message
    message.update!(deleted_by_sender_at: Time.current)
    assert_not_includes Message.visible_to(@sender), message
    assert_includes Message.visible_to(@recipient), message
  end

  test 'visible_to excludes recipient when recipient soft-deleted' do
    message = create_message
    message.update!(deleted_by_recipient_at: Time.current)
    assert_includes Message.visible_to(@sender), message
    assert_not_includes Message.visible_to(@recipient), message
  end

  test 'visible_to excludes unrelated users' do
    message = create_message
    assert_not_includes Message.visible_to(@other), message
  end

  # ─── trash_for scope ──────────────────────────────────────────────

  test 'trash_for includes rows recipient deleted within retention window' do
    message = create_message
    message.update!(deleted_by_recipient_at: 3.days.ago)
    assert_includes Message.trash_for(@recipient), message
  end

  test 'trash_for excludes rows whose recipient deletion is past retention' do
    message = create_message
    message.update!(deleted_by_recipient_at: (Message::TRASH_RETENTION + 1.day).ago)
    assert_not_includes Message.trash_for(@recipient), message
  end

  test 'trash_for includes sender side when sender deleted within retention' do
    message = create_message
    message.update!(deleted_by_sender_at: 2.days.ago)
    assert_includes Message.trash_for(@sender), message
  end

  # ─── folder class method ──────────────────────────────────────────

  test 'folder :unread returns only unread recipient messages not deleted by recipient' do
    unread = create_message
    read_msg = create_message(subject: 'Read')
    read_msg.read!
    soft_deleted = create_message(subject: 'Deleted')
    soft_deleted.update!(deleted_by_recipient_at: Time.current)

    results = Message.folder(@recipient, :unread)
    assert_includes results, unread
    assert_not_includes results, read_msg
    assert_not_includes results, soft_deleted
  end

  test 'folder :read returns only read recipient messages not deleted by recipient' do
    unread = create_message
    read_msg = create_message(subject: 'Read')
    read_msg.read!
    soft_deleted_read = create_message(subject: 'Deleted')
    soft_deleted_read.read!
    soft_deleted_read.update!(deleted_by_recipient_at: Time.current)

    results = Message.folder(@recipient, :read)
    assert_includes results, read_msg
    assert_not_includes results, unread
    assert_not_includes results, soft_deleted_read
  end

  test 'folder :sent returns sender messages not deleted by sender' do
    sent = create_message(subject: 'Sent')
    deleted_by_sender = create_message(subject: 'Gone')
    deleted_by_sender.update!(deleted_by_sender_at: Time.current)

    results = Message.folder(@sender, :sent)
    assert_includes results, sent
    assert_not_includes results, deleted_by_sender
  end

  test 'folder :all includes inbox and sent for the user, excluding their soft-deletes' do
    inbox = create_message(subject: 'Inbox')
    sent = Message.create!(sender: @recipient, recipient: @other, subject: 'Outbox', body: 'Test')
    deleted_by_recipient = create_message(subject: 'Gone R')
    deleted_by_recipient.update!(deleted_by_recipient_at: Time.current)
    deleted_by_sender = Message.create!(sender: @recipient, recipient: @other, subject: 'Gone S', body: 'Test')
    deleted_by_sender.update!(deleted_by_sender_at: Time.current)

    results = Message.folder(@recipient, :all)
    assert_includes results, inbox
    assert_includes results, sent
    assert_not_includes results, deleted_by_recipient
    assert_not_includes results, deleted_by_sender
  end

  test 'folder :trash includes only messages the user deleted within retention window' do
    recent_del = create_message(subject: 'Recent')
    recent_del.update!(deleted_by_recipient_at: 5.days.ago)
    expired_del = create_message(subject: 'Expired')
    expired_del.update!(deleted_by_recipient_at: 60.days.ago)
    not_deleted = create_message(subject: 'Kept')

    results = Message.folder(@recipient, :trash)
    assert_includes results, recent_del
    assert_not_includes results, expired_del
    assert_not_includes results, not_deleted
  end

  test 'folder returns none for unknown folder names' do
    create_message
    assert_equal 0, Message.folder(@recipient, :garbage).count
  end

  # ─── delete_for ───────────────────────────────────────────────────

  test 'delete_for(recipient) sets only deleted_by_recipient_at' do
    message = create_message
    message.delete_for(@recipient)
    assert_not_nil message.reload.deleted_by_recipient_at
    assert_nil message.deleted_by_sender_at
  end

  test 'delete_for(sender) sets only deleted_by_sender_at' do
    message = create_message
    message.delete_for(@sender)
    assert_not_nil message.reload.deleted_by_sender_at
    assert_nil message.deleted_by_recipient_at
  end

  test 'delete_for(user) on a self-message sets both timestamps' do
    message = Message.create!(sender: @sender, recipient: @sender, subject: 'Self', body: 'Test')
    message.delete_for(@sender)
    message.reload
    assert_not_nil message.deleted_by_sender_at
    assert_not_nil message.deleted_by_recipient_at
  end

  test 'delete_for is idempotent' do
    message = create_message
    message.delete_for(@recipient)
    first_ts = message.reload.deleted_by_recipient_at
    travel 1.minute do
      message.delete_for(@recipient)
    end
    assert_equal first_ts, message.reload.deleted_by_recipient_at
  end

  test 'delete_for on unrelated user is a no-op' do
    message = create_message
    assert_equal false, message.delete_for(@other)
    assert_nil message.reload.deleted_by_sender_at
    assert_nil message.reload.deleted_by_recipient_at
  end

  # ─── restore_for ──────────────────────────────────────────────────

  test 'restore_for clears recipient deletion within retention window' do
    message = create_message
    message.update!(deleted_by_recipient_at: 5.days.ago)
    message.restore_for(@recipient)
    assert_nil message.reload.deleted_by_recipient_at
  end

  test 'restore_for is a no-op once past retention' do
    message = create_message
    deleted_at = 60.days.ago
    message.update!(deleted_by_recipient_at: deleted_at)
    message.restore_for(@recipient)
    assert_in_delta deleted_at, message.reload.deleted_by_recipient_at, 1
  end

  test 'restore_for only touches the calling user side' do
    message = create_message
    message.update!(
      deleted_by_sender_at: 5.days.ago,
      deleted_by_recipient_at: 5.days.ago
    )
    message.restore_for(@recipient)
    message.reload
    assert_nil message.deleted_by_recipient_at
    assert_not_nil message.deleted_by_sender_at
  end

  # ─── visible_to? / deleted_by? / in_trash_for? ────────────────────

  test 'visible_to? true for sender and recipient until they soft-delete' do
    message = create_message
    assert message.visible_to?(@sender)
    assert message.visible_to?(@recipient)
    message.delete_for(@recipient)
    assert message.visible_to?(@sender)
    assert_not message.visible_to?(@recipient)
  end

  test 'visible_to? false for unrelated users' do
    message = create_message
    assert_not message.visible_to?(@other)
  end

  test 'deleted_by? reflects per-side deletion' do
    message = create_message
    assert_not message.deleted_by?(@sender)
    assert_not message.deleted_by?(@recipient)
    message.delete_for(@recipient)
    assert message.deleted_by?(@recipient)
    assert_not message.deleted_by?(@sender)
  end

  test 'in_trash_for? only within retention window' do
    message = create_message
    message.update!(deleted_by_recipient_at: 5.days.ago)
    assert message.in_trash_for?(@recipient)
    message.update!(deleted_by_recipient_at: 60.days.ago)
    assert_not message.in_trash_for?(@recipient)
  end

  # ─── Associations ─────────────────────────────────────────────────

  test 'user sent_messages association' do
    message = create_message
    assert_includes @sender.sent_messages, message
  end

  test 'user received_messages association' do
    message = create_message
    assert_includes @recipient.received_messages, message
  end
end
