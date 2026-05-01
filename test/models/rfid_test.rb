require 'test_helper'

class RfidTest < ActiveSupport::TestCase
  teardown do
    Current.reset
  end

  test 'creating a key fob creates a highlighted journal entry' do
    actor = users(:two)
    user = users(:one)
    Current.user = actor

    assert_difference -> { user.journals.count }, 1 do
      Rfid.create!(user: user, rfid: 'RFID-NEW-001', notes: 'Front door fob')
    end

    journal = user.journals.order(:created_at).last
    assert_equal 'key_fob_added', journal.action
    assert_equal actor, journal.actor_user
    assert journal.highlight?
    assert_equal 'RFID-NEW-001', journal.changes_json.dig('key_fob', 'rfid')
    assert_equal 'Front door fob', journal.changes_json.dig('key_fob', 'notes')
  end

  test 'destroying a key fob creates a highlighted journal entry' do
    actor = users(:two)
    rfid = rfids(:one)
    user = rfid.user
    Current.user = actor

    assert_difference -> { user.journals.count }, 1 do
      rfid.destroy!
    end

    journal = user.journals.order(:created_at).last
    assert_equal 'key_fob_removed', journal.action
    assert_equal actor, journal.actor_user
    assert journal.highlight?
    assert_equal 'RFID001', journal.changes_json.dig('key_fob', 'rfid')
    assert_equal "User one's card", journal.changes_json.dig('key_fob', 'notes')
  end
end
