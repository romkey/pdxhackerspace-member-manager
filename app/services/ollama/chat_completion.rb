# frozen_string_literal: true

module Ollama
  # POST /api/chat — non-streaming; optional JSON format for structured replies.
  class ChatCompletion
    TIMEOUT = 120

    Result = Struct.new(:ok, :assistant_content, :error, keyword_init: true)

    def self.call(base_url:, model:, system:, user:, format_json: false)
      new(base_url: base_url, model: model, system: system, user: user, format_json: format_json).call
    end

    def initialize(base_url:, model:, system:, user:, format_json: false)
      @root = base_url.to_s.strip.chomp('/')
      @model = model.to_s.strip
      @system = system.to_s
      @user = user.to_s
      @format_json = format_json
    end

    def call
      return Result.new(ok: false, assistant_content: nil, error: 'Base URL is blank') if @root.blank?
      return Result.new(ok: false, assistant_content: nil, error: 'Model is blank') if @model.blank?

      body = {
        model: @model,
        messages: [
          { role: 'system', content: @system },
          { role: 'user', content: @user }
        ],
        stream: false
      }
      body[:format] = 'json' if @format_json

      connection = Faraday.new(url: @root) do |f|
        f.options.timeout = TIMEOUT
        f.options.open_timeout = TIMEOUT
        f.adapter Faraday.default_adapter
      end

      response = connection.post('/api/chat') do |req|
        req.headers['Content-Type'] = 'application/json'
        req.headers['Accept'] = 'application/json'
        req.body = JSON.generate(body)
      end
      unless response.success?
        return Result.new(ok: false, assistant_content: nil, error: "HTTP #{response.status}: #{response.body.to_s.truncate(500)}")
      end

      parsed = JSON.parse(response.body)
      content = parsed.dig('message', 'content')
      return Result.new(ok: false, assistant_content: nil, error: 'Empty assistant message') if content.blank?

      Result.new(ok: true, assistant_content: content.to_s, error: nil)
    rescue JSON::ParserError => e
      Result.new(ok: false, assistant_content: nil, error: "Invalid JSON: #{e.message}")
    rescue Faraday::Error => e
      Result.new(ok: false, assistant_content: nil, error: e.message.presence || e.class.name)
    end
  end
end
