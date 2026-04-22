require 'test_helper'

class MessageTrashCleanupJobTest < ActiveJob::TestCase
  setup do
    @sender = users(:one)
    @recipient = users(:two)
  end

  def build_message(attrs = {})
    Message.create!(
      {
        sender: @sender,
        recipient: @recipient,
        subject: 'Hi',
        body: 'body'
      }.merge(attrs)
    )
  end

  test 'destroys messages where both sides deleted more than 30 days ago' do
    message = build_message
    message.update!(
      deleted_by_sender_at: 45.days.ago,
      deleted_by_recipient_at: 45.days.ago
    )

    assert_difference 'Message.count', -1 do
      MessageTrashCleanupJob.perform_now
    end

    assert_nil Message.find_by(id: message.id)
  end

  test 'keeps messages where only one side has deleted' do
    only_sender = build_message
    only_sender.update!(deleted_by_sender_at: 45.days.ago)

    only_recipient = build_message
    only_recipient.update!(deleted_by_recipient_at: 45.days.ago)

    assert_no_difference 'Message.count' do
      MessageTrashCleanupJob.perform_now
    end
  end

  test 'keeps messages where both sides deleted but one is still within retention' do
    message = build_message
    message.update!(
      deleted_by_sender_at: 60.days.ago,
      deleted_by_recipient_at: 10.days.ago
    )

    assert_no_difference 'Message.count' do
      MessageTrashCleanupJob.perform_now
    end
  end

  test 'keeps messages neither side deleted' do
    build_message

    assert_no_difference 'Message.count' do
      MessageTrashCleanupJob.perform_now
    end
  end

  test 'is idempotent across runs' do
    message = build_message
    message.update!(
      deleted_by_sender_at: 45.days.ago,
      deleted_by_recipient_at: 45.days.ago
    )

    MessageTrashCleanupJob.perform_now
    assert_no_difference 'Message.count' do
      MessageTrashCleanupJob.perform_now
    end
  end
end
