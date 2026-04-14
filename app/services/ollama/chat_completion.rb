# frozen_string_literal: true

module Ollama
  # POST /api/chat — non-streaming; optional JSON format for structured replies.
  class ChatCompletion
    TIMEOUT = 120

    Result = Struct.new(:ok, :assistant_content, :error)

    def self.call(base_url:, model:, system:, user:, options: {})
      new(
        base_url: base_url,
        model: model,
        system: system,
        user: user,
        options: options
      ).call
    end

    def initialize(base_url:, model:, system:, user:, options: {})
      @root = base_url.to_s.strip.chomp('/')
      @model = model.to_s.strip
      @system = system.to_s
      @user = user.to_s
      @format_json = options.fetch(:format_json, false)
      @api_key = options.fetch(:api_key, nil).to_s.strip
    end

    def call
      return failure(nil, 'Base URL is blank') if @root.blank?
      return failure(nil, 'Model is blank') if @model.blank?

      response = post_chat
      return http_failure(response) unless response.success?

      success_from_response(response)
    rescue JSON::ParserError => e
      failure(nil, "Invalid JSON: #{e.message}")
    rescue Faraday::Error => e
      failure(nil, e.message.presence || e.class.name)
    end

    private

    def failure(content, err)
      Result.new(false, content, err)
    end

    def success(content)
      Result.new(true, content, nil)
    end

    def build_body
      body = {
        model: @model,
        messages: [
          { role: 'system', content: @system },
          { role: 'user', content: @user }
        ],
        stream: false
      }
      body[:format] = 'json' if @format_json
      body
    end

    def faraday_connection
      Faraday.new(url: @root) do |f|
        f.options.timeout = TIMEOUT
        f.options.open_timeout = TIMEOUT
        f.adapter Faraday.default_adapter
      end
    end

    def post_chat
      faraday_connection.post('/api/chat') do |req|
        req.headers['Content-Type'] = 'application/json'
        req.headers['Accept'] = 'application/json'
        req.headers['Authorization'] = "Bearer #{@api_key}" if @api_key.present?
        req.body = JSON.generate(build_body)
      end
    end

    def http_failure(response)
      snippet = response.body.to_s.truncate(500)
      failure(nil, "HTTP #{response.status}: #{snippet}")
    end

    def success_from_response(response)
      parsed = JSON.parse(response.body)
      content = parsed.dig('message', 'content')
      return failure(nil, 'Empty assistant message') if content.blank?

      success(content.to_s)
    end
  end
end
