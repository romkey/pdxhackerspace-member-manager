# frozen_string_literal: true

require 'test_helper'

class MembershipApplicationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_local_auth_enabled = Rails.application.config.x.local_auth.enabled
    Rails.application.config.x.local_auth.enabled = true
    sign_in_as_admin
    @page = ApplicationFormPage.create!(title: 'Controller Import Page', position: 901)
    @page.questions.create!(label: 'Name', field_type: 'text', required: false, position: 1)
  end

  teardown do
    Rails.application.config.x.local_auth.enabled = @original_local_auth_enabled
  end

  test 'import creates membership application from csv' do
    file = fixture_file_upload('membership_application_import.csv', 'text/csv')

    assert_difference('MembershipApplication.count', 1) do
      post import_membership_applications_path, params: { file: file }
    end

    assert_redirected_to membership_applications_path
    follow_redirect!
    assert_match(/Imported 1 application/, flash[:notice])

    app = MembershipApplication.find_by!(email: 'controller-csv-import@example.com')
    assert_equal 'approved', app.status
    assert_equal 'Sam Sample', app.answer_for(@page.questions.first)&.value
  end

  test 'import without file redirects with alert' do
    post import_membership_applications_path
    assert_redirected_to membership_applications_path
    assert_equal 'Please choose a CSV file to import.', flash[:alert]
  end

  private

  def sign_in_as_admin
    account = local_accounts(:active_admin)
    post local_login_path, params: {
      session: { email: account.email, password: 'localpassword123' }
    }
  end
end
