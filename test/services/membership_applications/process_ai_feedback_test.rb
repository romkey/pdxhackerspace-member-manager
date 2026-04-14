# frozen_string_literal: true

require 'test_helper'

module MembershipApplications
  class ProcessAiFeedbackTest < ActiveSupport::TestCase
    setup do
      @profile = ai_ollama_profiles(:application_status)
      @profile.update!(
        enabled: true,
        base_url: 'http://ollama.test:11434',
        model: 'test-model',
        prompt: 'You review applications.'
      )
      ai_ollama_profiles(:default).update!(base_url: '', model: '')

      @application = MembershipApplication.create!(email: 'ai-feedback-test@example.com', status: 'draft')
      @application.update_columns(status: 'submitted', submitted_at: Time.current, updated_at: Time.current)
    end

    test 'stores parsed JSON from Ollama on success' do
      payload = {
        'score' => 1,
        'score_rationale' => 'Clear and complete.',
        'recommendation' => 'accept',
        'questions' => ['What shop do you prefer?'],
        'garbage' => false,
        'garbage_reason' => nil
      }

      stub_result = Ollama::ChatCompletion::Result.new(true, JSON.generate(payload), nil)
      with_chat_completion_stub(stub_result) do
        result = ProcessAiFeedback.call(application: @application)
        assert result.success?, result.message
      end

      @application.reload
      assert @application.ai_feedback_processed?
      assert_equal 1, @application.ai_feedback_score
      assert_equal 'Clear and complete.', @application.ai_feedback_score_rationale
      assert_equal 'accept', @application.ai_feedback_recommendation
      assert_equal ['What shop do you prefer?'], @application.ai_feedback_questions
      assert_not @application.ai_feedback_garbage
      assert_nil @application.ai_feedback_garbage_reason
      assert_nil @application.ai_feedback_last_error
    end

    test 'skips when already processed' do
      @application.update!(
        ai_feedback_processed_at: Time.current,
        ai_feedback_score: 5,
        ai_feedback_questions: []
      )

      result = ProcessAiFeedback.call(application: @application)
      assert result.skipped?
    end

    test 'records error when Ollama fails' do
      stub_result = Ollama::ChatCompletion::Result.new(false, nil, 'timeout')
      with_chat_completion_stub(stub_result) do
        result = ProcessAiFeedback.call(application: @application)
        assert result.failure?
      end

      @application.reload
      assert_nil @application.ai_feedback_processed_at
      assert_match(/timeout/, @application.ai_feedback_last_error)
    end

    test 'uses default profile endpoint and model when application_status leaves them blank' do
      @profile.update!(base_url: '', model: '')
      ai_ollama_profiles(:default).update!(base_url: 'http://default.test:11434', model: 'default-model')

      minimal_json = {
        'score' => 0,
        'score_rationale' => 'x',
        'recommendation' => 'needs_review',
        'questions' => [],
        'garbage' => false,
        'garbage_reason' => nil
      }
      stub_body = JSON.generate(minimal_json)

      called = nil
      with_chat_completion_stub(lambda { |**kwargs|
        called = kwargs
        Ollama::ChatCompletion::Result.new(true, stub_body, nil)
      }) do
        ProcessAiFeedback.call(application: @application)
      end

      assert_equal 'http://default.test:11434', called[:base_url]
      assert_equal 'default-model', called[:model]
    end

    private

    def with_chat_completion_stub(result_or_callable)
      original_call = Ollama::ChatCompletion.method(:call)
      replacement = result_or_callable.respond_to?(:call) ? result_or_callable : ->(**) { result_or_callable }
      Ollama::ChatCompletion.define_singleton_method(:call) do |**kwargs|
        replacement.call(**kwargs)
      end
      yield
    ensure
      Ollama::ChatCompletion.define_singleton_method(:call, original_call)
    end
  end
end
