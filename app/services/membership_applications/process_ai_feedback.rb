# frozen_string_literal: true

module MembershipApplications
  # Runs the Application Status Ollama profile against a submitted application and persists the JSON result.
  class ProcessAiFeedback
    JSON_INSTRUCTION = <<~TXT.squish
      Respond with a single JSON object only (no markdown fences), using exactly these keys:
      "score" (integer),
      "score_rationale" (string, one sentence),
      "recommendation" (string, e.g. "accept", "reject", or "needs_review"),
      "questions" (array of strings; clarifying questions, may be empty),
      "garbage" (boolean),
      "garbage_reason" (string or null).
    TXT

    Result = Struct.new(:status, :message) do
      def skipped?
        status == :skipped
      end

      def success?
        status == :success
      end

      def failure?
        status == :failure
      end
    end

    def self.call(application:)
      new(application: application).call
    end

    def initialize(application:)
      @application = application
    end

    def call
      return Result.new(:skipped, 'Draft applications are not processed') if @application.draft?
      return Result.new(:skipped, 'Already processed') if @application.ai_feedback_processed?

      profile = AiOllamaProfile.find_by(key: 'application_status')
      return Result.new(:failure, 'Application Status profile disabled') unless profile&.enabled?

      base_url = profile.effective_base_url
      model = profile.effective_model
      return Result.new(:failure, 'AI not configured') if base_url.blank? || model.blank?

      run_ollama_and_persist(profile, base_url, model)
    end

    private

    def run_ollama_and_persist(profile, base_url, model)
      parts = [profile.prompt.to_s.strip, JSON_INSTRUCTION]
      system_prompt = parts.compact_blank.join("\n\n")
      user_prompt = "Here is the membership application:\n\n#{@application.application_text_for_ai}"

      completion = Ollama::ChatCompletion.call(
        base_url: base_url,
        model: model,
        system: system_prompt.presence || JSON_INSTRUCTION,
        user: user_prompt,
        options: {
          api_key: profile.effective_api_key,
          format_json: true
        }
      )

      return handle_completion_failure(completion) unless completion.ok

      data = parse_feedback_json(completion.assistant_content)
      return handle_parse_failure unless data

      persist_feedback!(data)
      Result.new(:success, 'Stored AI feedback')
    end

    def handle_completion_failure(completion)
      record_error!(completion.error)
      Result.new(:failure, completion.error)
    end

    def handle_parse_failure
      record_error!('Could not parse JSON from model response')
      Result.new(:failure, 'Invalid JSON from model')
    end

    def record_error!(msg)
      @application.update_columns(
        ai_feedback_last_error: msg.to_s.truncate(2000),
        updated_at: Time.current
      )
    end

    def parse_feedback_json(raw)
      text = raw.to_s.strip
      text = text.sub(/\A```(?:json)?\s*/i, '').sub(/\s*```\z/, '')
      h = JSON.parse(text)
      return nil unless h.is_a?(Hash)

      score = h['score']
      score = Integer(score) if score.present?

      questions = h['questions']
      questions = [] if questions.nil?
      questions = [questions] if questions.is_a?(String)
      return nil unless questions.is_a?(Array)

      questions = questions.map { |q| q.to_s.strip }.compact_blank

      garbage = ActiveModel::Type::Boolean.new.cast(h.fetch('garbage', false))

      {
        score: score,
        score_rationale: h['score_rationale'].to_s,
        recommendation: h['recommendation'].to_s,
        questions: questions,
        garbage: garbage,
        garbage_reason: h['garbage_reason'].presence
      }
    rescue ArgumentError, JSON::ParserError
      nil
    end

    def persist_feedback!(data)
      @application.update!(
        ai_feedback_score: data[:score],
        ai_feedback_score_rationale: data[:score_rationale].presence,
        ai_feedback_recommendation: data[:recommendation].presence,
        ai_feedback_questions: data[:questions],
        ai_feedback_garbage: data[:garbage],
        ai_feedback_garbage_reason: data[:garbage_reason],
        ai_feedback_processed_at: Time.current,
        ai_feedback_last_error: nil
      )
    end
  end
end
