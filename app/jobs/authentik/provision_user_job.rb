module Authentik
  # Creates or links a User record in Authentik immediately after creation.
  # Checks if the user already exists by username and links them; otherwise creates a new account.
  class ProvisionUserJob < ApplicationJob
    queue_as :default

    def perform(user_id)
      user = User.find_by(id: user_id)
      return unless user
      return if user.authentik_id.present?

      Rails.logger.info(
        '[Authentik::ProvisionUserJob] Provisioning user ' \
        "#{user_id} (#{user.display_name}) in Authentik"
      )

      client = Authentik::Client.new

      username = user.username.presence || user.email.presence
      if username.blank?
        Rails.logger.warn("[Authentik::ProvisionUserJob] Skipping user #{user_id}: no username or email")
        return
      end

      name = user.full_name.presence || user.display_name

      # Link existing Authentik account if username already exists
      existing = client.find_user_by_username(username)
      if existing
        authentik_id = existing['pk'].to_s
        user.update_columns(authentik_id: authentik_id, last_synced_at: Time.current, authentik_dirty: false)
        sync_application_group_memberships(user)
        Rails.logger.info(
          '[Authentik::ProvisionUserJob] Linked existing Authentik user ' \
          "#{authentik_id} to user #{user_id}"
        )
        return
      end

      result = client.create_user(
        username: username,
        name: name,
        email: user.email,
        is_active: user.active?,
        attributes: { 'member_manager_id' => user_id.to_s }
      )

      authentik_id = result['pk'].to_s
      user.update_columns(authentik_id: authentik_id, last_synced_at: Time.current, authentik_dirty: false)
      sync_application_group_memberships(user)
      Rails.logger.info("[Authentik::ProvisionUserJob] Created Authentik user #{authentik_id} for user #{user_id}")
    rescue StandardError => e
      Rails.logger.error("[Authentik::ProvisionUserJob] Failed to provision user #{user_id}: #{e.class} #{e.message}")
      raise
    end

    private

    def sync_application_group_memberships(user)
      sources = %w[all_members]
      sources << 'active_members' if user.active?
      sources << 'unbanned_members' unless user.banned?
      sources << 'admin_members' if user.is_admin?

      Authentik::ApplicationGroupMembershipSyncJob.perform_later(sources)
    end
  end
end
