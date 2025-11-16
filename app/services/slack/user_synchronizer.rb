module Slack
  class UserSynchronizer
    def initialize(client: Client.new, logger: Rails.logger)
      @client = client
      @logger = logger
    end

    def call
      members = @client.list_users
      synced_ids = []

      SlackUser.transaction do
        members.each do |attrs|
          synced_ids << attrs[:slack_id]
          upsert_member(attrs)
        end
        deactivate_missing_members(synced_ids)
      end

      synced_ids.count
    end

    private

    def upsert_member(attrs)
      record = SlackUser.find_or_initialize_by(slack_id: attrs[:slack_id])
      record.assign_attributes(attrs)
      record.save!
    rescue ActiveRecord::RecordInvalid => e
      @logger.error("Failed to sync Slack user #{attrs[:slack_id]}: #{e.message}")
    end

    def deactivate_missing_members(synced_ids)
      return if synced_ids.empty?

      SlackUser.where.not(slack_id: synced_ids).where(deleted: false).update_all(deleted: true, updated_at: Time.current)
    end
  end
end

