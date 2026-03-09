require 'test_helper'

class UsersHelperTest < ActionView::TestCase
  include UsersHelper

  setup do
    @filter_params = {}
  end

  # ─── Basic toggling ──────────────────────────────────────────────

  test 'adds a filter when none are active' do
    path = stacking_filter_path(:dues_status, 'lapsed')
    assert_includes path, 'dues_status=lapsed'
  end

  test 'removes a filter when clicking the same value' do
    @filter_params = { dues_status: 'lapsed' }
    path = stacking_filter_path(:dues_status, 'lapsed')
    assert_not_includes path, 'dues_status'
  end

  test 'replaces a filter when clicking a different value in same category' do
    @filter_params = { dues_status: 'lapsed' }
    path = stacking_filter_path(:dues_status, 'current')
    assert_includes path, 'dues_status=current'
    assert_not_includes path, 'lapsed'
  end

  # ─── Stacking across categories ─────────────────────────────────

  test 'preserves existing filters when adding a new category' do
    @filter_params = { dues_status: 'lapsed' }
    path = stacking_filter_path(:membership_status, 'paying')
    assert_includes path, 'dues_status=lapsed'
    assert_includes path, 'membership_status=paying'
  end

  test 'preserves other filters when toggling one off' do
    @filter_params = { dues_status: 'lapsed', membership_status: 'paying' }
    path = stacking_filter_path(:dues_status, 'lapsed')
    assert_not_includes path, 'dues_status'
    assert_includes path, 'membership_status=paying'
  end

  test 'stacks three filters correctly' do
    @filter_params = { dues_status: 'lapsed', membership_status: 'paying' }
    path = stacking_filter_path(:payment_type, 'paypal')
    assert_includes path, 'dues_status=lapsed'
    assert_includes path, 'membership_status=paying'
    assert_includes path, 'payment_type=paypal'
  end

  # ─── Nil value handling ─────────────────────────────────────────

  test 'nil value removes the filter key' do
    @filter_params = { include_legacy: '1', dues_status: 'lapsed' }
    path = stacking_filter_path(:include_legacy, nil)
    assert_not_includes path, 'include_legacy'
    assert_includes path, 'dues_status=lapsed'
  end

  test 'nil value on absent key is a no-op' do
    @filter_params = { dues_status: 'lapsed' }
    path = stacking_filter_path(:include_legacy, nil)
    assert_not_includes path, 'include_legacy'
    assert_includes path, 'dues_status=lapsed'
  end

  # ─── Legacy toggle ──────────────────────────────────────────────

  test 'adds include_legacy when not present' do
    @filter_params = { dues_status: 'lapsed' }
    path = stacking_filter_path(:include_legacy, '1')
    assert_includes path, 'include_legacy=1'
    assert_includes path, 'dues_status=lapsed'
  end

  # ─── Sort params preserved ──────────────────────────────────────

  test 'preserves sort and direction params' do
    @filter_params = { sort: 'email', direction: 'desc' }
    path = stacking_filter_path(:dues_status, 'lapsed')
    assert_includes path, 'sort=email'
    assert_includes path, 'direction=desc'
    assert_includes path, 'dues_status=lapsed'
  end
end
