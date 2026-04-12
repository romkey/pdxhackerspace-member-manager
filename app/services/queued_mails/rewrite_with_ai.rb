# frozen_string_literal: true

module QueuedMails
  class RewriteWithAi
    JSON_INSTRUCTION = <<~TXT.squish
      Respond with a single JSON object only (no markdown fences), using exactly these keys:
      "body_html" (string),
      "body_text" (string).
      Keep placeholders/template tokens unchanged.
    TXT

    Result = Struct.new(:status, :message, :body_html, :body_text) do
      def success?
        status == :success
      end
    end

    def self.call(queued_mail:, subject:, body_html:, body_text:)
      new(queued_mail: queued_mail, subject: subject, body_html: body_html, body_text: body_text).call
    end

    def initialize(queued_mail:, subject:, body_html:, body_text:)
      @queued_mail = queued_mail
      @subject = subject.to_s
      @body_html = body_html.to_s
      @body_text = body_text.to_s
    end

    def call
      profile = AiOllamaProfile.find_by(key: 'email_rewriting')
      return Result.new(:failure, 'Email Rewriting AI profile is disabled.') unless profile&.enabled?

      base_url = profile.effective_base_url
      model = profile.effective_model
      return Result.new(:failure, 'Email Rewriting AI profile is not configured.') if base_url.blank? || model.blank?

      system_prompt = [profile.prompt.to_s.strip, JSON_INSTRUCTION].compact_blank.join("\n\n")
      completion = Ollama::ChatCompletion.call(
        base_url: base_url,
        model: model,
        system: system_prompt,
        user: build_user_prompt,
        format_json: true
      )
      return Result.new(:failure, completion.error.presence || 'Rewrite failed.') unless completion.ok

      parsed = parse_json(completion.assistant_content)
      return Result.new(:failure, 'AI response was not valid JSON.') unless parsed

      Result.new(:success, 'Message rewritten.', parsed[:body_html], parsed[:body_text])
    rescue StandardError => e
      Result.new(:failure, "Rewrite failed: #{e.message}")
    end

    private

    def build_user_prompt
      <<~PROMPT
        Rewrite this queued email body.

        Subject:
        #{@subject}

        Current HTML body:
        #{@body_html}

        Current plain text body:
        #{@body_text}
      PROMPT
    end

    def parse_json(raw)
      json = JSON.parse(raw.to_s)
      return nil unless json.is_a?(Hash)

      {
        body_html: json['body_html'].to_s,
        body_text: json['body_text'].to_s
      }
    rescue JSON::ParserError
      nil
    end
  end
end
