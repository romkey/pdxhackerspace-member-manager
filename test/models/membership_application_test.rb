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
