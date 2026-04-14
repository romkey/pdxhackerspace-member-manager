module Ollama
  class HealthCheck
    TIMEOUT = 5

    def self.call(base_url:, api_key: nil)
      new(base_url: base_url, api_key: api_key).call
    end

    def initialize(base_url:, api_key: nil)
      @root = base_url.to_s.strip.chomp('/')
      @api_key = api_key.to_s.strip
    end

    def call
      return Result.new(ok: false, error: 'Base URL is blank') if @root.blank?

      connection = Faraday.new(url: @root) do |f|
        f.options.timeout = TIMEOUT
        f.options.open_timeout = TIMEOUT
        f.adapter Faraday.default_adapter
      end
      response = connection.get('/api/tags') do |req|
        req.headers['Authorization'] = "Bearer #{@api_key}" if @api_key.present?
      end
      return Result.new(ok: false, error: "HTTP #{response.status}") unless response.success?

      JSON.parse(response.body)
      Result.new(ok: true, error: nil)
    rescue JSON::ParserError => e
      Result.new(ok: false, error: "Invalid response: #{e.message}")
    rescue Faraday::Error => e
      Result.new(ok: false, error: e.message.presence || e.class.name)
    end

    Result = Struct.new(:ok, :error)
  end
end
