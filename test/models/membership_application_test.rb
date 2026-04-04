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
