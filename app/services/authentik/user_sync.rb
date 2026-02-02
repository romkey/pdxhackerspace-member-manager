module Authentik
  class UserSync
    # Fields that can be synced to Authentik
    SYNCABLE_FIELDS = %w[email full_name username active].freeze

    # Mapping from MemberManager field names to Authentik field names
    FIELD_MAPPING = {
      'email' => 'email',
      'full_name' => 'name',
      'username' => 'username',
      'active' => 'is_active'
    }.freeze

    attr_reader :user, :client

    def initialize(user, client: nil)
      @user = user
      @client = client || Authentik::Client.new
    end

    # Push user changes to Authentik
    def sync_to_authentik!(changed_fields: nil)
      return { status: 'skipped', reason: 'no_authentik_id' } if user.authentik_id.blank?
      return { status: 'skipped', reason: 'api_not_configured' } unless api_configured?

      # Determine which fields to sync
      fields_to_sync = if changed_fields.present?
                         changed_fields & SYNCABLE_FIELDS
                       else
                         SYNCABLE_FIELDS
                       end

      return { status: 'skipped', reason: 'no_syncable_changes' } if fields_to_sync.empty?

      Rails.logger.info("[Authentik::UserSync] Syncing user #{user.id} (#{user.authentik_id}) to Authentik: #{fields_to_sync.join(', ')}")

      # Build the update payload
      attrs = {}
      fields_to_sync.each do |field|
        authentik_field = FIELD_MAPPING[field]
        attrs[authentik_field] = user.send(field)
      end

      begin
        client.update_user(user.authentik_id, **attrs)
        user.update_column(:last_synced_at, Time.current)

        Rails.logger.info("[Authentik::UserSync] Successfully synced user #{user.id} to Authentik")
        { status: 'synced', authentik_id: user.authentik_id, fields: fields_to_sync }
      rescue StandardError => e
        Rails.logger.error("[Authentik::UserSync] Failed to sync user to Authentik: #{e.message}")
        { status: 'error', error: e.message }
      end
    end

    # Pull user changes from Authentik
    def sync_from_authentik!
      return { status: 'skipped', reason: 'no_authentik_id' } if user.authentik_id.blank?
      return { status: 'skipped', reason: 'api_not_configured' } unless api_configured?

      Rails.logger.info("[Authentik::UserSync] Fetching user #{user.id} (#{user.authentik_id}) from Authentik")

      begin
        authentik_data = client.get_user(user.authentik_id)
        apply_authentik_data(authentik_data)
      rescue StandardError => e
        Rails.logger.error("[Authentik::UserSync] Failed to fetch user from Authentik: #{e.message}")
        { status: 'error', error: e.message }
      end
    end

    # Apply Authentik data to the local user record
    def apply_authentik_data(authentik_data, skip_if_no_changes: true)
      changes = {}

      # Map Authentik fields to User fields
      if authentik_data['email'].present? && authentik_data['email'] != user.email
        changes[:email] = authentik_data['email']
      end

      if authentik_data['name'].present? && authentik_data['name'] != user.full_name
        changes[:full_name] = authentik_data['name']
      end

      if authentik_data['username'].present? && authentik_data['username'] != user.username
        changes[:username] = authentik_data['username']
      end

      # Note: We intentionally don't sync is_active to active automatically
      # because active status in MemberManager has different business logic

      return { status: 'no_changes' } if changes.empty? && skip_if_no_changes

      Rails.logger.info("[Authentik::UserSync] Applying changes to user #{user.id}: #{changes.keys.join(', ')}")

      user.update!(changes.merge(last_synced_at: Time.current))

      { status: 'updated', changes: changes.keys }
    rescue StandardError => e
      Rails.logger.error("[Authentik::UserSync] Failed to apply Authentik data: #{e.message}")
      { status: 'error', error: e.message }
    end

    # Class method for batch sync of all users with Authentik IDs
    def self.sync_all_to_authentik!
      results = { synced: 0, skipped: 0, errors: 0 }

      User.where.not(authentik_id: [nil, '']).find_each do |user|
        result = new(user).sync_to_authentik!
        case result[:status]
        when 'synced' then results[:synced] += 1
        when 'skipped' then results[:skipped] += 1
        when 'error' then results[:errors] += 1
        end
      end

      results
    end

    private

    def api_configured?
      AuthentikConfig.settings.api_token.present? && AuthentikConfig.settings.api_base_url.present?
    end
  end
end
