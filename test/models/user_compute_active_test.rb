require 'test_helper'

class UserComputeActiveTest < ActiveSupport::TestCase
  # ─── compute_active_status callback ────────────────────────────────

  test 'paying member with current dues is active' do
    user = build_user(membership_status: 'paying', dues_status: 'current')
    user.save!
    assert user.active?, 'paying + current should be active'
  end

  test 'paying member with lapsed dues is inactive' do
    user = build_user(membership_status: 'paying', dues_status: 'lapsed')
    user.save!
    assert_not user.active?, 'paying + lapsed should be inactive'
  end

  test 'paying member with unknown dues is inactive' do
    user = build_user(membership_status: 'paying', dues_status: 'unknown')
    user.save!
    assert_not user.active?, 'paying + unknown should be inactive'
  end

  test 'sponsored member without end date is active' do
    user = build_user(membership_status: 'sponsored', dues_status: 'inactive')
    user.save!
    assert user.active?, 'sponsored without dues_due_at should be active'
  end

  test 'sponsored member with expired limited access is inactive' do
    user = build_user(membership_status: 'sponsored', dues_status: 'current', dues_due_at: 1.day.ago)
    user.save!
    assert_not user.active?, 'sponsored with past dues_due_at should be inactive'
  end

  test 'guest member without end date is active' do
    user = build_user(membership_status: 'guest', dues_status: 'unknown')
    user.save!
    assert user.active?, 'guest without dues_due_at should be active'
  end

  test 'guest member with expired limited access is inactive' do
    user = build_user(membership_status: 'guest', dues_status: 'unknown', dues_due_at: 2.days.ago)
    user.save!
    assert_not user.active?, 'guest with past dues_due_at should be inactive'
  end

  test 'is_sponsored flag respects limited duration expiry' do
    user = build_user(
      membership_status: 'paying',
      dues_status: 'current',
      is_sponsored: true,
      dues_due_at: 1.hour.ago
    )
    user.save!
    assert_not user.active?, 'sponsored flag with expired dues_due_at should be inactive'
  end

  test 'banned member is always inactive' do
    user = build_user(membership_status: 'banned', dues_status: 'current')
    user.save!
    assert_not user.active?, 'banned should always be inactive'
  end

  test 'deceased member is always inactive' do
    user = build_user(membership_status: 'deceased', dues_status: 'current')
    user.save!
    assert_not user.active?, 'deceased should always be inactive'
  end

  test 'deceased member gets payment_type set to inactive' do
    user = build_user(membership_status: 'deceased', payment_type: 'paypal')
    user.save!
    assert_equal 'inactive', user.payment_type
  end

  test 'applicant member is always inactive' do
    user = build_user(membership_status: 'applicant', dues_status: 'current')
    user.save!
    assert_not user.active?, 'applicant should always be inactive'
  end

  test 'cancelled member with current dues is active' do
    user = build_user(membership_status: 'cancelled', dues_status: 'current')
    user.save!
    assert user.active?, 'cancelled + current should be active'
  end

  test 'cancelled member with lapsed dues is inactive' do
    user = build_user(membership_status: 'cancelled', dues_status: 'lapsed')
    user.save!
    assert_not user.active?, 'cancelled + lapsed should be inactive'
  end

  test 'unknown membership with current dues is active' do
    user = build_user(membership_status: 'unknown', dues_status: 'current')
    user.save!
    assert user.active?, 'unknown + current should be active'
  end

  test 'unknown membership with unknown dues is inactive' do
    user = build_user(membership_status: 'unknown', dues_status: 'unknown')
    user.save!
    assert_not user.active?, 'unknown + unknown should be inactive'
  end

  # ─── Service account exemption ─────────────────────────────────────

  test 'service account active flag is not overridden by compute_active_status' do
    user = build_user(membership_status: 'unknown', dues_status: 'unknown', service_account: true, active: true)
    user.save!
    assert user.active?, 'service account active flag should not be overridden'
  end

  test 'service account can be set to inactive regardless of status' do
    user = build_user(membership_status: 'paying', dues_status: 'current', service_account: true, active: false)
    user.save!
    assert_not user.active?, 'service account inactive flag should be preserved'
  end

  # ─── Transition scenarios ──────────────────────────────────────────

  test 'changing membership status from paying to banned deactivates user' do
    user = build_user(membership_status: 'paying', dues_status: 'current')
    user.save!
    assert user.active?

    user.membership_status = 'banned'
    user.save!
    assert_not user.active?, 'banning should deactivate'
  end

  test 'changing dues from lapsed to current activates paying member' do
    user = build_user(membership_status: 'paying', dues_status: 'lapsed')
    user.save!
    assert_not user.active?

    user.dues_status = 'current'
    user.save!
    assert user.active?, 'becoming current should activate paying member'
  end

  private

  def build_user(attrs = {})
    defaults = {
      authentik_id: "test-#{SecureRandom.hex(4)}",
      full_name: "Test User #{SecureRandom.hex(4)}",
      payment_type: attrs[:payment_type] || 'unknown',
      membership_status: 'unknown',
      dues_status: 'unknown',
      service_account: false,
      active: false,
      profile_visibility: 'members'
    }
    User.new(defaults.merge(attrs))
  end
end
