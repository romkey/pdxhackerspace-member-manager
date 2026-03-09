module Authentik
  class ApplicationGroupMembershipSyncJob < ApplicationJob
    queue_as :default

    def perform(member_sources)
      return unless api_configured?

      groups = ApplicationGroup.with_authentik_group_id.with_member_sources(member_sources)
      return if groups.empty?

      Rails.logger.info(
        "[ApplicationGroupMembershipSyncJob] Syncing #{groups.count} groups " \
        "for sources: #{member_sources.join(', ')}"
      )

      groups.find_each do |group|
        sync = Authentik::GroupSync.new(group)
        result = sync.sync_members!
        Rails.logger.info("[ApplicationGroupMembershipSyncJob] Synced #{group.name}: #{result[:status]}")
      rescue StandardError => e
        Rails.logger.error("[ApplicationGroupMembershipSyncJob] Failed to sync #{group.name}: #{e.message}")
      end
    end

    private

    def api_configured?
      AuthentikConfig.settings.api_token.present? && AuthentikConfig.settings.api_base_url.present?
    end
  end
end
