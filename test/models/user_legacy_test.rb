require 'test_helper'

class UserLegacyTest < ActiveSupport::TestCase
  # ─── Scopes ────────────────────────────────────────────────────────

  test 'legacy scope returns only legacy users' do
    legacy_user = create_user(legacy: true)
    regular_user = create_user(legacy: false)

    assert_includes User.legacy, legacy_user
    assert_not_includes User.legacy, regular_user
  end

  test 'non_legacy scope excludes legacy users' do
    legacy_user = create_user(legacy: true)
    regular_user = create_user(legacy: false)

    assert_not_includes User.non_legacy, legacy_user
    assert_includes User.non_legacy, regular_user
  end

  test 'legacy defaults to false' do
    user = User.new(authentik_id: 'test-default', full_name: 'Default Test', payment_type: 'unknown')
    assert_not user.legacy?
  end

  # ─── Journal suppression: marking as legacy ────────────────────────

  test 'marking as legacy does not create a journal entry' do
    user = create_user(legacy: false)
    initial_journal_count = user.journals.count

    user.update!(legacy: true)

    assert_equal initial_journal_count, user.journals.count,
                 'No journal entry should be created when marking as legacy'
  end

  test 'marking as legacy with other changes still creates a journal entry' do
    user = create_user(legacy: false, full_name: 'Old Name')
    initial_journal_count = user.journals.count

    user.update!(legacy: true, full_name: 'New Name')

    assert_operator user.journals.count, :>, initial_journal_count,
                    'Journal entry should be created when legacy is set alongside other changes'
  end

  # ─── Journal entry: un-marking legacy ──────────────────────────────

  test 'un-marking legacy creates a journal entry' do
    user = create_user(legacy: true)
    initial_journal_count = user.journals.count

    user.update!(legacy: false)

    assert_operator user.journals.count, :>, initial_journal_count,
                    'Journal entry should be created when un-marking legacy'
  end

  # ─── Auto-clear legacy when meaningful data arrives ────────────────

  test 'setting a membership plan clears legacy flag' do
    plan = MembershipPlan.create!(name: "Auto-clear Plan #{SecureRandom.hex(4)}", cost: 50,
                                  billing_frequency: 'monthly', plan_type: 'primary')
    user = create_user(legacy: true)

    user.update!(membership_plan: plan)

    assert_not user.legacy?, 'Legacy should be cleared when a membership plan is set'
  end

  test 'setting dues_status to current clears legacy flag' do
    user = create_user(legacy: true, dues_status: 'unknown')

    user.update!(dues_status: 'current')

    assert_not user.legacy?, 'Legacy should be cleared when dues_status changes to current'
  end

  test 'setting dues_status to lapsed clears legacy flag' do
    user = create_user(legacy: true, dues_status: 'unknown')

    user.update!(dues_status: 'lapsed')

    assert_not user.legacy?, 'Legacy should be cleared when dues_status changes to lapsed'
  end

  test 'setting dues_status to inactive clears legacy flag' do
    user = create_user(legacy: true, dues_status: 'unknown')

    user.update!(dues_status: 'inactive')

    assert_not user.legacy?, 'Legacy should be cleared when dues_status changes to inactive'
  end

  test 'dues_status remaining unknown does NOT clear legacy flag' do
    user = create_user(legacy: true, dues_status: 'unknown')

    user.update!(full_name: "Updated Name #{SecureRandom.hex(4)}")

    assert user.legacy?, 'Legacy should NOT be cleared when dues_status stays unknown'
  end

  test 'setting last_payment_date clears legacy flag' do
    user = create_user(legacy: true)

    user.update!(last_payment_date: Date.current)

    assert_not user.legacy?, 'Legacy should be cleared when last_payment_date is set'
  end

  test 'setting recharge_most_recent_payment_date clears legacy flag' do
    user = create_user(legacy: true)

    user.update!(recharge_most_recent_payment_date: Time.current)

    assert_not user.legacy?, 'Legacy should be cleared when recharge_most_recent_payment_date is set'
  end

  test 'setting membership_status to paying clears legacy flag' do
    user = create_user(legacy: true, membership_status: 'unknown')

    user.update!(membership_status: 'paying')

    assert_not user.legacy?, 'Legacy should be cleared when membership_status becomes paying'
  end

  test 'setting membership_status to sponsored clears legacy flag' do
    user = create_user(legacy: true, membership_status: 'unknown')

    user.update!(membership_status: 'sponsored')

    assert_not user.legacy?, 'Legacy should be cleared when membership_status becomes sponsored'
  end

  # ─── Regression: setting legacy must not be undone by existing data ──

  test 'marking legacy sticks even when dues_status is inactive' do
    user = create_user(legacy: false, dues_status: 'inactive')

    user.update!(legacy: true)
    user.reload

    assert user.legacy?, 'Legacy should stick when set on a member with existing inactive dues_status'
  end

  test 'marking legacy sticks even when dues_status is lapsed' do
    user = create_user(legacy: false, dues_status: 'lapsed')

    user.update!(legacy: true)
    user.reload

    assert user.legacy?, 'Legacy should stick when set on a member with existing lapsed dues_status'
  end

  test 'marking legacy sticks even when membership_plan is set' do
    plan = MembershipPlan.create!(name: "Sticky Plan #{SecureRandom.hex(4)}", cost: 50, billing_frequency: 'monthly',
                                  plan_type: 'primary')
    user = create_user(legacy: false)
    user.update_columns(membership_plan_id: plan.id)

    user.update!(legacy: true)
    user.reload

    assert user.legacy?, 'Legacy should stick when set on a member that already has a plan'
  end

  # ─── Auto-clear journal ────────────────────────────────────────────

  test 'auto-clear of legacy creates a journal entry' do
    user = create_user(legacy: true, dues_status: 'unknown')
    initial_journal_count = user.journals.count

    user.update!(dues_status: 'current')

    assert_not user.legacy?
    assert_operator user.journals.count, :>, initial_journal_count,
                    'Journal entry should be created when legacy is auto-cleared'
  end

  private

  def create_user(attrs = {})
    defaults = {
      authentik_id: "legacy-test-#{SecureRandom.hex(4)}",
      full_name: "Legacy Test #{SecureRandom.hex(4)}",
      payment_type: attrs[:payment_type] || 'unknown',
      membership_status: attrs[:membership_status] || 'unknown',
      dues_status: attrs[:dues_status] || 'unknown',
      legacy: false
    }
    User.create!(defaults.merge(attrs))
  end
end
