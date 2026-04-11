# frozen_string_literal: true

require 'test_helper'

class PagesControllerTest < ActionDispatch::IntegrationTest
  teardown do
    MembershipSetting.instance.update!(use_builtin_membership_application: true)
  end

  test 'apply redirects to built-in gate when builtin flow is enabled' do
    MembershipSetting.instance.update!(use_builtin_membership_application: true)

    get apply_path

    assert_redirected_to apply_new_path
  end

  test 'apply shows apply fragment when external flow is enabled' do
    MembershipSetting.instance.update!(use_builtin_membership_application: false)
    TextFragment.ensure_exists!(
      key: 'apply_for_membership',
      title: 'Apply for membership',
      content: '<p>External apply fragment body</p>'
    )

    get apply_path

    assert_response :success
    assert_match 'External apply fragment body', response.body
  end
end
