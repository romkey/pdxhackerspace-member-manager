# frozen_string_literal: true

require 'test_helper'

class ApplicationFormPagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_local_auth_enabled = Rails.application.config.x.local_auth.enabled
    Rails.application.config.x.local_auth.enabled = true
    sign_in_as_local_admin
  end

  teardown do
    Rails.application.config.x.local_auth.enabled = @original_local_auth_enabled
    MembershipSetting.instance.update!(use_builtin_membership_application: true)
  end

  test 'update_application_flow toggles membership setting' do
    MembershipSetting.instance.update!(use_builtin_membership_application: true)

    patch update_application_flow_application_form_pages_path,
          params: { use_builtin_membership_application: '0' }

    assert_redirected_to application_form_pages_path
    assert_not MembershipSetting.instance.reload.use_builtin_membership_application?

    patch update_application_flow_application_form_pages_path,
          params: { use_builtin_membership_application: '1' }

    assert_redirected_to application_form_pages_path
    assert MembershipSetting.instance.reload.use_builtin_membership_application?
  end

  test 'update_application_flow without choice shows alert' do
    patch update_application_flow_application_form_pages_path, params: {}

    assert_redirected_to application_form_pages_path
    assert_equal 'Choose how applicants should apply.', flash[:alert]
  end

  private

  def sign_in_as_local_admin
    account = local_accounts(:active_admin)
    post local_login_path, params: {
      session: {
        email: account.email,
        password: 'localpassword123'
      }
    }
  end
end
