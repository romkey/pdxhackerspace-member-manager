# frozen_string_literal: true

# Also see MembershipApplicationTest for admin_search scope tests and index?q tests below.
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

  test 'non-admin cannot view membership application show' do
    app = MembershipApplication.create!(
      email: 'non-admin-denied@example.com',
      status: 'submitted',
      submitted_at: Time.current
    )

    delete logout_path
    account = local_accounts(:regular_member)
    post local_login_path, params: {
      session: { email: account.email, password: 'memberpassword123' }
    }

    get membership_application_path(app)

    assert_redirected_to user_path(users(:member_with_local_account))
    assert_equal 'You do not have access to that section.', flash[:alert]
  end

  test 'link_user associates member with application' do
    app = MembershipApplication.create!(
      email: 'link-app-test@example.com',
      status: 'submitted',
      submitted_at: Time.current
    )
    member = users(:member_with_local_account)

    post link_user_membership_application_path(app), params: { user_id: member.id }

    assert_redirected_to membership_application_path(app)
    assert_match(/linked/i, flash[:notice])
    assert_equal member.id, app.reload.user_id
  end

  test 'index search filters by query param' do
    q_page = ApplicationFormPage.create!(title: 'Idx Search Page', position: 9989)
    qq = q_page.questions.create!(label: 'Note', field_type: 'text', required: false, position: 1)
    hit = MembershipApplication.create!(
      email: 'idx-search-hit@example.com', status: 'submitted', submitted_at: Time.current
    )
    hit.application_answers.create!(application_form_question: qq, value: 'idx-unique-needle')
    miss = MembershipApplication.create!(
      email: 'idx-search-miss@example.com', status: 'submitted', submitted_at: Time.current
    )

    get membership_applications_path(q: 'idx-unique-needle')

    assert_response :success
    assert_select 'a[href=?]', membership_application_path(hit)
    assert_select 'a[href=?]', membership_application_path(miss), count: 0
  end

  test 'index defaults to open submitted tab' do
    open_app = MembershipApplication.create!(
      email: 'default-open@example.com',
      status: 'submitted',
      submitted_at: Time.current
    )
    closed_app = MembershipApplication.create!(
      email: 'default-approved@example.com',
      status: 'approved',
      submitted_at: Time.current,
      reviewed_at: Time.current
    )

    get membership_applications_path

    assert_response :success
    assert_select 'a.nav-link.active', text: /Open/
    assert_select 'a[href=?]', membership_application_path(open_app)
    assert_select 'a[href=?]', membership_application_path(closed_app), count: 0
  end

  test 'index unlinked tab lists only approved applications without a linked member' do
    linked_member = users(:member_with_local_account)
    keep = MembershipApplication.create!(
      email: 'unlinked-approved@example.com',
      status: 'approved',
      submitted_at: Time.current,
      reviewed_at: Time.current
    )
    filtered_open = MembershipApplication.create!(
      email: 'unlinked-open@example.com',
      status: 'submitted',
      submitted_at: Time.current
    )
    filtered_rejected = MembershipApplication.create!(
      email: 'unlinked-rejected@example.com',
      status: 'rejected',
      submitted_at: Time.current,
      reviewed_at: Time.current
    )
    filtered_linked = MembershipApplication.create!(
      email: 'linked-approved@example.com',
      status: 'approved',
      submitted_at: Time.current,
      reviewed_at: Time.current,
      user: linked_member
    )

    get membership_applications_path(status: 'unlinked')

    assert_response :success
    assert_select 'a.nav-link.active', text: /Unlinked/
    assert_select 'a[href=?]', membership_application_path(keep)
    assert_select 'a[href=?]', membership_application_path(filtered_open), count: 0
    assert_select 'a[href=?]', membership_application_path(filtered_rejected), count: 0
    assert_select 'a[href=?]', membership_application_path(filtered_linked), count: 0
  end

  test 'index unlinked count includes only approved without a linked member' do
    MembershipApplication.create!(
      email: 'badge-open-unlinked@example.com',
      status: 'submitted',
      submitted_at: Time.current
    )
    MembershipApplication.create!(
      email: 'badge-approved-unlinked@example.com',
      status: 'approved',
      submitted_at: Time.current,
      reviewed_at: Time.current
    )
    MembershipApplication.create!(
      email: 'badge-rejected-unlinked@example.com',
      status: 'rejected',
      submitted_at: Time.current,
      reviewed_at: Time.current
    )

    get membership_applications_path(status: 'all')

    assert_response :success
    expected_count = MembershipApplication.where(status: 'approved').where(user_id: nil).count
    assert_select "a[href='#{membership_applications_path(status: 'unlinked')}'] span.badge",
                  text: expected_count.to_s
  end

  test 'show masks applicant contact when Executive Director topic exists and viewer is not trained' do
    TrainingTopic.create!(name: 'Executive Director')
    sign_in_as_admin
    app = membership_application_with_sensitive_answers
    get membership_application_path(app)

    assert_response :success
    assert_includes response.body, 'data-controller="sensitive-reveal"'
    assert_includes response.body, 'data-sensitive-reveal-target="blurred"'
    assert_includes response.body, 'Show contact details'
  end

  test 'show does not mask when Executive Director training topic is not in database' do
    sign_in_as_admin
    app = membership_application_with_sensitive_answers
    get membership_application_path(app)

    assert_response :success
    assert_no_match(/data-controller="sensitive-reveal"/, response.body)
  end

  test 'show does not mask when viewer has Executive Director training' do
    topic = TrainingTopic.create!(name: 'Executive Director')
    sign_in_as_admin
    admin = User.find(session[:user_id])
    Training.create!(trainee: admin, training_topic: topic, trained_at: Time.current)
    app = membership_application_with_sensitive_answers
    get membership_application_path(app)

    assert_response :success
    assert_no_match(/data-controller="sensitive-reveal"/, response.body)
  end

  test 'vote_ai_feedback creates vote when AI feedback processed' do
    sign_in_as_admin
    app = MembershipApplication.create!(
      email: 'vote-ai@example.com',
      status: 'submitted',
      submitted_at: Time.current,
      ai_feedback_processed_at: Time.current,
      ai_feedback_recommendation: 'accept'
    )
    assert_difference -> { app.reload.ai_feedback_votes.count }, 1 do
      post vote_ai_feedback_membership_application_path(app), params: {
        ai_feedback_vote: { stance: 'agree', reason: 'Matches my read' }
      }
    end
    assert_redirected_to membership_application_path(app)
    vote = app.ai_feedback_votes.last
    assert_equal 'agree', vote.stance
    assert_equal 'Matches my read', vote.reason
  end

  test 'vote_ai_feedback updates existing vote for same admin' do
    sign_in_as_admin
    admin = User.find(session[:user_id])
    app = MembershipApplication.create!(
      email: 'vote-update@example.com',
      status: 'submitted',
      submitted_at: Time.current,
      ai_feedback_processed_at: Time.current,
      ai_feedback_recommendation: 'reject'
    )
    MembershipApplicationAiFeedbackVote.create!(
      membership_application: app,
      user: admin,
      stance: 'agree',
      reason: 'First'
    )
    assert_no_difference -> { app.reload.ai_feedback_votes.count } do
      post vote_ai_feedback_membership_application_path(app), params: {
        ai_feedback_vote: { stance: 'disagree', reason: 'Changed mind' }
      }
    end
    vote = app.reload.ai_feedback_votes.sole
    assert_equal 'disagree', vote.stance
    assert_equal 'Changed mind', vote.reason
  end

  test 'vote_ai_feedback rejected when AI not processed' do
    sign_in_as_admin
    app = MembershipApplication.create!(
      email: 'vote-no-ai@example.com',
      status: 'submitted',
      submitted_at: Time.current
    )
    assert_no_difference -> { MembershipApplicationAiFeedbackVote.count } do
      post vote_ai_feedback_membership_application_path(app), params: {
        ai_feedback_vote: { stance: 'agree', reason: '' }
      }
    end
    assert_redirected_to membership_application_path(app)
    assert_equal 'Admin feedback is only available after AI feedback has been processed.', flash[:alert]
  end

  test 'show includes AI feedback section for non-draft applications' do
    app = MembershipApplication.create!(
      email: 'show-ai-section@example.com',
      status: 'submitted',
      submitted_at: Time.current
    )

    get membership_application_path(app)

    assert_response :success
    assert_match(/AI feedback/i, response.body)
  end

  test 'approve blocked when executive director topic exists and admin lacks training' do
    TrainingTopic.create!(name: 'Executive Director')
    app = MembershipApplication.create!(
      email: 'approve-gate@example.com',
      status: 'submitted',
      submitted_at: Time.current
    )
    assert_no_changes -> { app.reload.status } do
      post approve_membership_application_path(app), params: { admin_notes: 'n' }
    end
    assert_redirected_to membership_application_path(app)
    assert_match(/Executive Director/i, flash[:alert].to_s)
  end

  test 'approve allowed when admin has executive director training' do
    topic = TrainingTopic.create!(name: 'Executive Director')
    admin = User.find(session[:user_id])
    Training.create!(trainee: admin, training_topic: topic, trained_at: Time.current)
    page1 = ApplicationFormPage.create!(title: 'First page', position: 1)
    q_name = page1.questions.create!(label: 'Name', field_type: 'text', required: false, position: 1)
    app = MembershipApplication.create!(
      email: 'approve-ok@example.com',
      status: 'submitted',
      submitted_at: Time.current
    )
    app.application_answers.create!(application_form_question: q_name, value: 'Pat Applicant')
    qm = nil
    assert_difference 'User.count', 1 do
      assert_difference 'QueuedMail.count', 1 do
        post approve_membership_application_path(app), params: { admin_notes: 'Welcome' }
        qm = QueuedMail.order(:created_at).last
      end
    end
    assert_redirected_to edit_queued_mail_path(qm)
    app.reload
    assert_equal 'approved', app.status
    assert_equal 'Pat Applicant', app.user.full_name
    assert_equal 'approve-ok@example.com', app.user.email
    assert_equal 'application_approved', qm.mailer_action
    assert_equal app.user, qm.recipient
  end

  test 'reject redirects to edit queued mail when executive director' do
    topic = TrainingTopic.create!(name: 'Executive Director')
    admin = User.find(session[:user_id])
    Training.create!(trainee: admin, training_topic: topic, trained_at: Time.current)
    app = MembershipApplication.create!(
      email: 'reject-redirect@example.com',
      status: 'submitted',
      submitted_at: Time.current
    )

    assert_difference 'QueuedMail.count', 1 do
      post reject_membership_application_path(app), params: { admin_notes: 'Not a fit.' }
    end

    qm = QueuedMail.order(:created_at).last
    assert_redirected_to edit_queued_mail_path(qm)
    assert_equal 'rejected', app.reload.status
    assert_equal 'application_rejected', qm.mailer_action
  end

  test 'approve links existing user by email and still queues mail' do
    topic = TrainingTopic.create!(name: 'Executive Director')
    admin = User.find(session[:user_id])
    Training.create!(trainee: admin, training_topic: topic, trained_at: Time.current)
    existing = users(:two)
    app = MembershipApplication.create!(
      email: existing.email,
      status: 'submitted',
      submitted_at: Time.current
    )
    assert_no_difference 'User.count' do
      assert_difference 'QueuedMail.count', 1 do
        post approve_membership_application_path(app), params: {}
      end
    end
    assert_equal existing.id, app.reload.user_id
    assert_redirected_to edit_queued_mail_path(QueuedMail.order(:created_at).last)
  end

  test 'save_tour_feedback creates feedback for current admin' do
    app = MembershipApplication.create!(
      email: 'tour-save@example.com',
      status: 'submitted',
      submitted_at: Time.current
    )
    assert_difference -> { app.reload.tour_feedbacks.count }, 1 do
      post save_tour_feedback_membership_application_path(app), params: {
        tour_feedback: { attitude: 'Positive', impressions: '', engagement: '', fit_feeling: '' }
      }
    end
    assert_redirected_to membership_application_path(app)
    assert_equal 'Positive', app.tour_feedbacks.sole.attitude
  end

  test 'vote_acceptance records tally' do
    app = MembershipApplication.create!(
      email: 'vote-accept@example.com',
      status: 'submitted',
      submitted_at: Time.current
    )
    post vote_acceptance_membership_application_path(app), params: {
      acceptance_vote: { decision: 'accept' }
    }
    assert_redirected_to membership_application_path(app)
    assert_equal({ 'accept' => 1 }, app.reload.acceptance_vote_counts)
  end

  test 'vote_acceptance rejected when application finalized' do
    app = MembershipApplication.create!(
      email: 'vote-closed@example.com',
      status: 'approved',
      submitted_at: Time.current,
      reviewed_at: Time.current
    )
    assert_no_difference -> { MembershipApplicationAcceptanceVote.count } do
      post vote_acceptance_membership_application_path(app), params: {
        acceptance_vote: { decision: 'reject' }
      }
    end
    assert_redirected_to membership_application_path(app)
    assert_match(/pending/i, flash[:alert].to_s)
  end

  test 'unlink_user clears member on application' do
    app = MembershipApplication.create!(
      email: 'unlink-app-test@example.com',
      status: 'submitted',
      submitted_at: Time.current
    )
    member = users(:member_with_local_account)
    app.update!(user: member)

    post unlink_user_membership_application_path(app)

    assert_redirected_to membership_application_path(app)
    assert_nil app.reload.user_id
  end

  private

  def membership_application_with_sensitive_answers
    p1 = ApplicationFormPage.create!(title: 'Contact PII Page', position: 11_101)
    q_mail = p1.questions.create!(label: 'Mailing Address', field_type: 'text', required: false, position: 1)
    q_phone = p1.questions.create!(label: 'Phone number', field_type: 'text', required: false, position: 2)
    p2 = ApplicationFormPage.create!(title: 'Referral PII Page', position: 11_102)
    q_mem_email = p2.questions.create!(label: 'Member Email', field_type: 'text', required: false, position: 1)
    q_mem_phone = p2.questions.create!(label: 'Member Phone', field_type: 'text', required: false, position: 2)
    app = MembershipApplication.create!(
      email: 'pii-test@example.com',
      status: 'submitted',
      submitted_at: Time.current
    )
    app.application_answers.create!(application_form_question: q_mail, value: '123 Secret Street')
    app.application_answers.create!(application_form_question: q_phone, value: '555-000-1111')
    app.application_answers.create!(application_form_question: q_mem_email, value: 'referrer@example.com')
    app.application_answers.create!(application_form_question: q_mem_phone, value: '555-222-3333')
    app
  end

  def sign_in_as_admin
    account = local_accounts(:active_admin)
    post local_login_path, params: {
      session: { email: account.email, password: 'localpassword123' }
    }
  end
end
