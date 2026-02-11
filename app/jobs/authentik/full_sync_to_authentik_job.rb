module Authentik
  class FullSyncToAuthentikJob < ApplicationJob
    queue_as :default

    def perform
      client = Authentik::Client.new
      results = { users_synced: 0, users_skipped: 0, users_errored: 0, groups_synced: 0, groups_errored: 0 }

      # 1. Sync each member with an authentik_id to Authentik
      Rails.logger.info("[Authentik::FullSyncToAuthentik] Starting user sync...")
      User.where.not(authentik_id: [nil, '']).find_each do |user|
        sync_user_to_authentik(user, client, results)
      end

      # 2. Sync all ApplicationGroup groups
      Rails.logger.info("[Authentik::FullSyncToAuthentik] Syncing application groups...")
      ApplicationGroup.find_each do |app_group|
        sync_application_group(app_group, client, results)
      end

      # 3. Sync the active members group (the configured Authentik group)
      sync_active_members_group(client, results)

      Rails.logger.info("[Authentik::FullSyncToAuthentik] Complete: #{results.inspect}")
      results
    end

    private

    def sync_user_to_authentik(user, client, results)
      attrs = {}

      # Core fields
      attrs[:email] = user.email if user.email.present?
      attrs[:name] = user.full_name if user.full_name.present?
      attrs[:username] = user.username if user.username.present?
      attrs[:is_active] = user.active?

      # Write member_manager_id as extra data in attributes
      attrs[:attributes] = {
        'member_manager_id' => user.id.to_s
      }

      client.update_user(user.authentik_id, **attrs)
      user.update_column(:last_synced_at, Time.current)
      results[:users_synced] += 1

      Rails.logger.info("[Authentik::FullSyncToAuthentik] Synced user #{user.id} (#{user.display_name})")
    rescue StandardError => e
      results[:users_errored] += 1
      Rails.logger.error("[Authentik::FullSyncToAuthentik] Failed to sync user #{user.id}: #{e.message}")
    end

    def sync_application_group(app_group, client, results)
      group_sync = Authentik::GroupSync.new(app_group, client: client)
      result = group_sync.sync!

      if result[:status] == 'error'
        results[:groups_errored] += 1
        Rails.logger.error("[Authentik::FullSyncToAuthentik] Failed to sync group '#{app_group.name}': #{result[:error]}")
      else
        results[:groups_synced] += 1
        Rails.logger.info("[Authentik::FullSyncToAuthentik] Synced group '#{app_group.name}'")
      end
    rescue StandardError => e
      results[:groups_errored] += 1
      Rails.logger.error("[Authentik::FullSyncToAuthentik] Failed to sync group '#{app_group.name}': #{e.message}")
    end

    def sync_active_members_group(client, results)
      group_id = AuthentikConfig.settings.group_id
      return unless group_id.present?

      Rails.logger.info("[Authentik::FullSyncToAuthentik] Syncing active members group (#{group_id})...")

      # Get all active users with authentik_id
      active_user_pks = User.active.where.not(authentik_id: [nil, '']).pluck(:authentik_id).map(&:to_i)

      client.set_group_users(group_id, active_user_pks)
      Rails.logger.info("[Authentik::FullSyncToAuthentik] Active members group synced with #{active_user_pks.count} members")
    rescue StandardError => e
      Rails.logger.error("[Authentik::FullSyncToAuthentik] Failed to sync active members group: #{e.message}")
    end
  end
end
