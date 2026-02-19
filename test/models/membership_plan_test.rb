require 'test_helper'

class MembershipPlanTest < ActiveSupport::TestCase
  test 'shared plan scope excludes personal plans' do
    shared = MembershipPlan.shared
    assert shared.all? { |p| p.user_id.nil? }
  end

  test 'personal plan scope excludes shared plans' do
    personal = MembershipPlan.personal
    assert personal.all? { |p| p.user_id.present? }
  end

  test 'personal? returns true for plans with user_id' do
    plan = membership_plans(:personal_equipment_donation)
    assert plan.personal?
  end

  test 'personal? returns false for shared plans' do
    plan = membership_plans(:monthly_standard)
    assert_not plan.personal?
  end

  test 'personal plan enforces manual true' do
    user = users(:cash_payer)
    plan = MembershipPlan.new(
      name: 'Test Personal', cost: 50, billing_frequency: 'monthly',
      plan_type: 'primary', user: user, manual: false, visible: true, display_order: 1
    )
    plan.valid?
    assert plan.manual?, 'personal plan should enforce manual: true'
    assert_not plan.visible?, 'personal plan should enforce visible: false'
  end

  test 'personal plan enforces visible false' do
    user = users(:cash_payer)
    plan = MembershipPlan.new(
      name: 'Test Personal Visible', cost: 50, billing_frequency: 'monthly',
      plan_type: 'primary', user: user, visible: true, display_order: 1
    )
    plan.valid?
    assert_not plan.visible?
  end

  test 'shared plan name uniqueness is enforced' do
    existing = membership_plans(:monthly_standard)
    plan = MembershipPlan.new(
      name: existing.name, cost: 99, billing_frequency: 'monthly',
      plan_type: 'primary', display_order: 1
    )
    assert_not plan.valid?
    assert plan.errors.key?(:name)
  end

  test 'personal plans can share names with shared plans' do
    user = users(:cash_payer)
    existing = membership_plans(:monthly_standard)
    plan = MembershipPlan.new(
      name: existing.name, cost: 99, billing_frequency: 'monthly',
      plan_type: 'primary', user: user, display_order: 1
    )
    assert plan.valid?, plan.errors.full_messages.join(', ')
  end

  test 'personal plans can share names with other personal plans' do
    user = users(:one)
    plan = MembershipPlan.new(
      name: 'Equipment Donation', cost: 50, billing_frequency: 'monthly',
      plan_type: 'primary', user: user, display_order: 1
    )
    assert plan.valid?, plan.errors.full_messages.join(', ')
  end

  test 'display_name includes user name for personal plans' do
    plan = membership_plans(:personal_equipment_donation)
    assert_includes plan.display_name, plan.user.display_name
    assert_includes plan.display_name, plan.name
  end

  test 'display_name for shared plans does not include user name' do
    plan = membership_plans(:monthly_standard)
    assert_includes plan.display_name, plan.name
    assert_includes plan.display_name, format('%.2f', plan.cost)
  end
end
