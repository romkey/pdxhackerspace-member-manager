# frozen_string_literal: true

require 'test_helper'

class MembershipApplicationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test 'submit! enqueues AI feedback job' do
    app = MembershipApplication.create!(email: 'enqueue-ai-test@example.com', status: 'draft')

    assert_enqueued_with(job: MembershipApplicationAiFeedbackJob, args: [app.id]) do
      app.submit!
    end
  end

  test 'submit! emails staff trained as Executive Director' do
    topic = TrainingTopic.create!(name: MembershipApplication::EXECUTIVE_DIRECTOR_TRAINING_TOPIC_NAME)
    admin = users(:one)
    Training.create!(trainee: admin, training_topic: topic, trained_at: Time.current)
    app = MembershipApplication.create!(email: 'submit-ed-notify@example.com', status: 'draft')

    assert_difference 'ActionMailer::Base.deliveries.size', 1 do
      perform_enqueued_jobs only: ActionMailer::MailDeliveryJob do
        app.submit!
      end
    end

    assert_equal 'submitted', app.reload.status
    assert_enqueued_jobs 1, only: MembershipApplicationAiFeedbackJob
  end

  test 'delay_for_review! moves open application to under_review and journals' do
    app = MembershipApplication.create!(email: 'delay-review@example.com', status: 'submitted')
    admin = users(:one)

    assert_difference -> { Journal.where(action: 'application_delayed_for_review').count }, 1 do
      app.delay_for_review!(admin, notes: 'Need board input')
    end

    app.reload
    assert_equal 'under_review', app.status
    assert_equal admin, app.reviewed_by
    assert app.reviewed_at.present?
    assert_equal 'Need board input', app.admin_notes
  end

  test 'delay_for_review! raises when not open' do
    app = MembershipApplication.create!(email: 'delay-bad@example.com', status: 'approved',
                                        submitted_at: Time.current, reviewed_at: Time.current)

    assert_raises(ArgumentError) do
      app.delay_for_review!(users(:one))
    end
  end

  test 'reject! creates pending queued rejection mail' do
    app = MembershipApplication.create!(email: 'reject-mail-test@example.com', status: 'submitted')
    admin = users(:one)

    qm = nil
    assert_difference 'QueuedMail.count', 1 do
      qm = app.reject!(admin, notes: 'Does not meet requirements')
    end

    assert_equal 'rejected', app.reload.status
    assert_equal 'pending', qm.status
    assert_equal 'application_rejected', qm.mailer_action
    assert_equal app.email, qm.to
    assert_includes qm.body_html, 'Does not meet requirements'
  end

  test 'reject! queues mail to linked user email' do
    member = users(:member_with_local_account)
    app = MembershipApplication.create!(
      email: 'other@example.com',
      status: 'submitted',
      user: member
    )
    admin = users(:one)

    qm = app.reject!(admin, notes: nil)

    assert_equal member.email, qm.to
    assert_equal member, qm.recipient
  end

  test 'newest_first orders by submitted time (fallback created_at), then id desc' do
    travel_to Time.zone.local(2026, 4, 15, 12, 0, 0) do
      older = MembershipApplication.create!(
        email: 'order-old@example.com', status: 'submitted',
        submitted_at: 5.days.ago, created_at: 5.days.ago
      )
      newer = MembershipApplication.create!(
        email: 'order-new@example.com', status: 'submitted',
        submitted_at: 1.day.ago, created_at: 2.days.ago
      )
      ids = MembershipApplication.where(id: [older.id, newer.id]).newest_first.pluck(:id)
      assert_equal [newer.id, older.id], ids

      t = Time.current
      first = MembershipApplication.create!(
        email: 'tie-a@example.com', status: 'submitted', submitted_at: t, created_at: t
      )
      second = MembershipApplication.create!(
        email: 'tie-b@example.com', status: 'submitted', submitted_at: t, created_at: t
      )
      assert_operator second.id, :>, first.id
      tie_ids = MembershipApplication.where(id: [first.id, second.id]).newest_first.pluck(:id)
      assert_equal [second.id, first.id], tie_ids
    end
  end

  test 'admin_search matches email, answer text, and linked member fields' do
    page = ApplicationFormPage.create!(title: 'Search Page', position: 9988)
    q_bio = page.questions.create!(label: 'Bio', field_type: 'textarea', required: false, position: 1)

    by_email = MembershipApplication.create!(email: 'unique-sapphire@example.com', status: 'submitted')
    by_answer = MembershipApplication.create!(email: 'plain@example.com', status: 'submitted')
    by_answer.application_answers.create!(application_form_question: q_bio, value: 'unique-quasar-hobby')
    other = MembershipApplication.create!(email: 'other@example.com', status: 'submitted')

    ids = MembershipApplication.admin_search('unique-sapphire').pluck(:id)
    assert_includes ids, by_email.id
    assert_not_includes ids, other.id

    ids = MembershipApplication.admin_search('unique-quasar').pluck(:id)
    assert_includes ids, by_answer.id
    assert_not_includes ids, other.id

    member = users(:member_with_local_account)
    linked = MembershipApplication.create!(email: 'x@example.com', status: 'submitted', user: member)
    ids = MembershipApplication.admin_search('regularmember').pluck(:id)
    assert_includes ids, linked.id
  end

  test 'applicant_display_name uses name answer, linked user, or em dash' do
    page = ApplicationFormPage.create!(title: 'Test Contact', position: 9999)
    q = page.questions.create!(label: 'Name', field_type: 'text', required: false, position: 1)
    app = MembershipApplication.create!(email: 'applicant-name-test@example.com', status: 'submitted')

    assert_equal '—', app.applicant_display_name(name_question_id: q.id)

    app.application_answers.create!(application_form_question: q, value: '  Jane Doe  ')
    assert_equal 'Jane Doe', app.reload.applicant_display_name(name_question_id: q.id)

    app.application_answers.destroy_all
    member = users(:member_with_local_account)
    app.update!(user: member)
    assert_equal member.display_name, app.reload.applicant_display_name(name_question_id: q.id)
  end

  test 'ai_feedback_admin_vote_counts groups by stance with ordered association' do
    app = MembershipApplication.create!(email: 'vote-counts@example.com', status: 'submitted')
    MembershipApplicationAiFeedbackVote.create!(
      membership_application: app,
      user: users(:one),
      stance: 'agree'
    )
    MembershipApplicationAiFeedbackVote.create!(
      membership_application: app,
      user: users(:two),
      stance: 'disagree'
    )
    counts = app.reload.ai_feedback_admin_vote_counts
    assert_equal 1, counts['agree']
    assert_equal 1, counts['disagree']
  end

  test 'ai_feedback_recommendation_badge_color maps known recommendations' do
    app = MembershipApplication.new
    app.ai_feedback_recommendation = 'accept'
    assert_equal 'success', app.ai_feedback_recommendation_badge_color
    app.ai_feedback_recommendation = 'reject'
    assert_equal 'danger', app.ai_feedback_recommendation_badge_color
    app.ai_feedback_recommendation = 'needs_review'
    assert_equal 'warning', app.ai_feedback_recommendation_badge_color
    app.ai_feedback_recommendation = 'something_else'
    assert_equal 'secondary', app.ai_feedback_recommendation_badge_color
  end
end
