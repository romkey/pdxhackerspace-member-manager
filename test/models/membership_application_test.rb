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
end
