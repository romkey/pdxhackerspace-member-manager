module Authentik
  class UserSyncJob < ApplicationJob
    queue_as :default

    # Sync a user's changes to Authentik
    # @param user_id [Integer] The user's ID
    # @param changed_fields [Array<String>] The fields that changed (optional, syncs all if not provided)
    def perform(user_id, changed_fields = nil)
      user = User.find_by(id: user_id)
      return unless user
      return if user.authentik_id.blank?

      Rails.logger.info("[Authentik::UserSyncJob] Syncing user #{user_id} to Authentik")

      sync = Authentik::UserSync.new(user)
      result = sync.sync_to_authentik!(changed_fields: changed_fields)

      case result[:status]
      when 'synced'
        Rails.logger.info("[Authentik::UserSyncJob] User #{user_id} synced successfully")
      when 'skipped'
        Rails.logger.info("[Authentik::UserSyncJob] User #{user_id} sync skipped: #{result[:reason]}")
      when 'error'
        Rails.logger.error("[Authentik::UserSyncJob] User #{user_id} sync failed: #{result[:error]}")
      end
    rescue StandardError => e
      Rails.logger.error("[Authentik::UserSyncJob] Failed to sync user #{user_id}: #{e.class} #{e.message}")
      raise
    end
  end
end
