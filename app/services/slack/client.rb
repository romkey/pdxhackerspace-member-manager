require "faraday"

module Slack
  class Client
    USERS_LIST_ENDPOINT = "/api/users.list".freeze
    DEFAULT_LIMIT = 200

    def initialize(token: SlackConfig.settings.api_token, base_url: SlackConfig.settings.base_url)
      @token = token
      @base_url = base_url
    end

    def list_users
      raise ArgumentError, "Slack API token is missing" if @token.blank?

      members = []
      cursor = nil

      loop do
        response = connection.get(USERS_LIST_ENDPOINT, request_params(cursor))
        payload = JSON.parse(response.body)
        handle_error!(payload)

        members += extract_members(payload)
        cursor = payload.dig("response_metadata", "next_cursor").presence
        break if cursor.blank?
      end

      members
    end

    private

    def connection
      @connection ||= Faraday.new(url: @base_url) do |faraday|
        faraday.request :authorization, "Bearer", @token
        faraday.response :raise_error
        faraday.adapter Faraday.default_adapter
      end
    end

    def request_params(cursor)
      params = { limit: DEFAULT_LIMIT }
      params[:cursor] = cursor if cursor.present?
      params
    end

    def handle_error!(payload)
      return if payload["ok"]

      raise StandardError, "Slack API error: #{payload['error']}"
    end

    def extract_members(payload)
      Array(payload["members"]).map do |member|
        {
          slack_id: member["id"],
          team_id: member["team_id"],
          username: member["name"],
          real_name: member.dig("profile", "real_name"),
          display_name: member.dig("profile", "display_name"),
          email: normalize_email(member.dig("profile", "email")),
          title: member.dig("profile", "title"),
          phone: member.dig("profile", "phone"),
          tz: member["tz"],
          is_admin: truthy?(member["is_admin"]),
          is_owner: truthy?(member["is_owner"]),
          is_bot: truthy?(member["is_bot"]),
          deleted: truthy?(member["deleted"]),
          raw_attributes: member,
          last_synced_at: Time.current
        }
      end
    end

    def normalize_email(email)
      email.to_s.strip.presence
    end

    def truthy?(value)
      ActiveModel::Type::Boolean.new.cast(value) || false
    end
  end
end

