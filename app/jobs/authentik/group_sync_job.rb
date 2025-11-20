module Authentik
  class GroupSyncJob < ApplicationJob
    queue_as :default

    def perform
      ensure_api_configured!
      synced_count = GroupSynchronizer.new.call
      Rails.logger.info("Authentik group sync completed (#{synced_count} members).")
    rescue StandardError => e
      Rails.logger.error("Authentik group sync failed: #{e.class} #{e.message}")
      raise
    end

    private

    def ensure_api_configured!
      settings = AuthentikConfig.settings
      return if settings.api_token.present? && settings.group_id.present?

      raise 'Authentik API token and group ID are required for syncing.'
    end
  end
end
