module Authentik
  class GroupSynchronizer
    def initialize(client: Client.new, logger: Rails.logger)
      @client = client
      @logger = logger
    end

    def call
      unless MemberSource.enabled?('authentik')
        @logger.info('Authentik source is disabled — skipping sync.')
        return 0
      end

      members = @client.group_members(source_group_id)
      now = Time.current

      ActiveRecord::Base.transaction do
        upsert_members(members, now)
        prune_removed_authentik_users(members)
      end

      # Record sync in member source
      MemberSource.for('authentik').record_sync!

      members.count
    end

    private

    def source_group_id
      all_members_group&.authentik_group_id.presence || AuthentikConfig.settings.group_id
    end

    def all_members_group
      ApplicationGroup.with_member_sources('all_members').with_authentik_group_id.first
    end

    def upsert_members(members, timestamp)
      members.each do |attrs|
        user = find_matching_user(attrs)
        link_user_to_authentik!(user, attrs) if user
        sync_authentik_user(attrs, user, timestamp)
      rescue ActiveRecord::RecordInvalid => e
        @logger.error("Failed to sync Authentik user #{attrs.inspect}: #{e.message}")
      end
    end

    def prune_removed_authentik_users(members)
      synced_ids = members.filter_map { |attrs| attrs[:authentik_id].to_s.presence }
      removed_records = AuthentikUser.where.not(authentik_id: synced_ids)
      removed_count = removed_records.count
      return if removed_count.zero?

      removed_records.find_each do |authentik_user|
        unlink_member_from_removed_authentik_user!(authentik_user)
        authentik_user.destroy!
      end

      @logger.info("Deleted #{removed_count} local Authentik user(s) no longer present in Authentik.")
    end

    def unlink_member_from_removed_authentik_user!(authentik_user)
      user = authentik_user.user
      return unless user&.authentik_id == authentik_user.authentik_id

      user.update_columns(authentik_id: nil, authentik_dirty: false, updated_at: Time.current)
    end

    def find_matching_user(attrs)
      user = User.find_by(authentik_id: attrs[:authentik_id])
      user ||= find_user_by_email(attrs[:email])
      user ||= User.by_name_or_alias(attrs[:full_name]).first if attrs[:full_name].present?
      user
    end

    def find_user_by_email(email)
      return if email.blank?

      normalized_email = email.downcase
      User.find_by('LOWER(email) = ?', normalized_email) ||
        User.where('EXISTS (SELECT 1 FROM unnest(extra_emails) AS e WHERE LOWER(e) = ?)',
                   normalized_email).first
    end

    def link_user_to_authentik!(user, attrs)
      return if user.authentik_id.present?

      user.update_columns(authentik_id: attrs[:authentik_id], updated_at: Time.current)
      Authentik::ApplicationGroupMembershipSyncJob.perform_later(application_group_sources_for(user))
    end

    def application_group_sources_for(user)
      sources = %w[all_members]
      sources << 'active_members' if user.active?
      sources << 'unbanned_members' unless user.banned?
      sources << 'admin_members' if user.is_admin?
      sources
    end

    def sync_authentik_user(attrs, user, timestamp)
      authentik_user = AuthentikUser.find_or_initialize_by(authentik_id: attrs[:authentik_id])

      authentik_user.assign_attributes(
        username: attrs[:username],
        email: attrs[:email],
        full_name: attrs[:full_name],
        is_active: attrs[:active] != false,
        raw_attributes: (authentik_user.raw_attributes || {}).merge(
          'sync' => attrs[:attributes],
          'synced_at' => timestamp.iso8601
        ),
        last_synced_at: timestamp,
        user: user
      )

      authentik_user.save!
    rescue ActiveRecord::RecordInvalid => e
      @logger.error("Failed to sync AuthentikUser #{attrs[:authentik_id]}: #{e.message}")
    end
  end
end
