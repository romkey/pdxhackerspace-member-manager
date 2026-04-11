require 'test_helper'
require 'active_job/test_helper'

class ApplicationVerificationsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  teardown do
    MembershipSetting.instance.update!(use_builtin_membership_application: true)
  end

  # ─── Gate Page ───────────────────────────────────────────────────

  test 'gate page renders successfully' do
    get apply_new_path
    assert_response :success
    assert_match 'Membership Application', response.body
    assert_match 'attended an open house', response.body
    assert_match 'Code of Conduct', response.body
  end

  # ─── Validation Errors ──────────────────────────────────────────

  test 'rejects submission without open house confirmation' do
    post apply_new_path, params: {
      confirmed_code_of_conduct: '1',
      email: 'test@example.com'
    }
    assert_redirected_to apply_new_path
    assert_equal 'You must confirm that you have attended an open house.', flash[:alert]
  end

  test 'rejects submission without code of conduct confirmation' do
    post apply_new_path, params: {
      confirmed_open_house: '1',
      email: 'test@example.com'
    }
    assert_redirected_to apply_new_path
    assert_equal 'You must confirm that you have read and agree with the Code of Conduct.', flash[:alert]
  end

  test 'rejects submission with blank email' do
    post apply_new_path, params: {
      confirmed_open_house: '1',
      confirmed_code_of_conduct: '1',
      email: ''
    }
    assert_redirected_to apply_new_path
    assert_equal 'Please enter a valid email address.', flash[:alert]
  end

  test 'rejects submission with invalid email' do
    post apply_new_path, params: {
      confirmed_open_house: '1',
      confirmed_code_of_conduct: '1',
      email: 'not-an-email'
    }
    assert_redirected_to apply_new_path
    assert_equal 'Please enter a valid email address.', flash[:alert]
  end

  # ─── Successful Submission ──────────────────────────────────────

  test 'creates verification and sends email on valid submission' do
    assert_difference 'ApplicationVerification.count', 1 do
      assert_enqueued_emails 1 do
        post apply_new_path, params: {
          confirmed_open_house: '1',
          confirmed_code_of_conduct: '1',
          email: 'applicant@example.com'
        }
      end
    end

    assert_redirected_to apply_check_email_path
    verification = ApplicationVerification.last
    assert_equal 'applicant@example.com', verification.email
    assert verification.confirmed_open_house?
    assert verification.confirmed_code_of_conduct?
    assert_not verification.email_verified?
  end

  # ─── Check Email Page ──────────────────────────────────────────

  test 'check_email page renders successfully' do
    get apply_check_email_path
    assert_response :success
    assert_match 'Check Your Email', response.body
  end

  # ─── Email Verification ────────────────────────────────────────

  test 'valid token verifies email and redirects to application' do
    verification = ApplicationVerification.create!(
      email: 'test@example.com',
      confirmed_open_house: true,
      confirmed_code_of_conduct: true
    )

    get apply_verify_email_path(token: verification.token)

    assert_redirected_to apply_start_path
    verification.reload
    assert verification.email_verified?
    assert_not_nil verification.verified_at
  end

  test 'invalid token redirects to gate with error' do
    get apply_verify_email_path(token: 'nonexistent')

    assert_redirected_to apply_new_path
    assert_equal 'Invalid verification link.', flash[:alert]
  end

  test 'expired token redirects to gate with error' do
    verification = ApplicationVerification.create!(
      email: 'test@example.com',
      confirmed_open_house: true,
      confirmed_code_of_conduct: true
    )
    verification.update_columns(expires_at: 1.hour.ago)

    get apply_verify_email_path(token: verification.token)

    assert_redirected_to apply_new_path
    assert_equal 'This verification link has expired. Please start over.', flash[:alert]
  end

  # ─── Application Guard ─────────────────────────────────────────

  test 'application start page redirects without verified token' do
    get apply_start_path
    assert_redirected_to apply_new_path
    assert_equal 'Please verify your email address before starting an application.', flash[:alert]
  end

  test 'application start page accessible with verified token' do
    verification = ApplicationVerification.create!(
      email: 'test@example.com',
      confirmed_open_house: true,
      confirmed_code_of_conduct: true
    )
    verification.verify_email!

    get apply_verify_email_path(token: verification.token)
    follow_redirect!

    assert_response :success
  end

  test 'application page redirects without verified token' do
    get apply_page_path(page_number: 1)
    assert_redirected_to apply_new_path
  end

  test 'application submit redirects without verified token' do
    post apply_submit_path
    assert_redirected_to apply_new_path
  end

  # ─── Code of Conduct PDF ────────────────────────────────────

  test 'code_of_conduct_pdf returns 404 when no document exists' do
    get apply_code_of_conduct_pdf_path
    assert_response :not_found
  end

  test 'code_of_conduct_pdf serves PDF when document exists' do
    Document.create!(
      title: 'Code of Conduct',
      file: fixture_file_upload('code-of-conduct.pdf', 'application/pdf')
    )

    get apply_code_of_conduct_pdf_path
    assert_response :success
    assert_equal 'application/pdf', response.media_type
  end

  # ─── Expired Verification ──────────────────────────────────

  test 'gate renders apply fragment when external application flow' do
    MembershipSetting.instance.update!(use_builtin_membership_application: false)
    TextFragment.ensure_exists!(
      key: 'apply_for_membership',
      title: 'Apply for membership',
      content: '<p>External apply content</p>'
    )

    get apply_new_path

    assert_response :success
    assert_match 'External apply content', response.body
    assert_no_match 'Send Verification Email', response.body
  end

  test 'external flow redirects verification post to apply page' do
    MembershipSetting.instance.update!(use_builtin_membership_application: false)

    assert_no_difference 'ApplicationVerification.count' do
      post apply_new_path, params: {
        confirmed_open_house: '1',
        confirmed_code_of_conduct: '1',
        email: 'applicant@example.com'
      }
    end

    assert_redirected_to apply_path
  end

  test 'expired verification blocks application access' do
    verification = ApplicationVerification.create!(
      email: 'test@example.com',
      confirmed_open_house: true,
      confirmed_code_of_conduct: true
    )
    verification.verify_email!

    get apply_verify_email_path(token: verification.token)

    verification.update_columns(expires_at: 1.hour.ago)

    get apply_start_path
    assert_redirected_to apply_new_path
  end
end
