module Authentik
  class GroupSynchronizer
    def initialize(client: Client.new, logger: Rails.logger)
      @client = client
      @logger = logger
    end

    def call
      members = @client.group_members
      now = Time.current

      ActiveRecord::Base.transaction do
        upsert_members(members, now)
        deactivate_missing_members(members)
      end

      # Record sync in member source
      MemberSource.for('authentik').record_sync!

      members.count
    end

    private

    def upsert_members(members, timestamp)
      members.each do |attrs|
        # First try to find by authentik_id
        user = User.find_by(authentik_id: attrs[:authentik_id])

        # If not found by authentik_id, try to find by email (case-insensitive)
        if user.nil? && attrs[:email].present?
          user = User.find_by('LOWER(email) = ?', attrs[:email].downcase)
          # If found by email, link the authentik_id
          user.authentik_id = attrs[:authentik_id] if user
        end

        # If still not found, create new
        user ||= User.new(authentik_id: attrs[:authentik_id])

        # Merge in missing information - only set if blank/nil
        user.email = attrs[:email] if user.email.blank? && attrs[:email].present?
        user.full_name = attrs[:full_name] if user.full_name.blank? && attrs[:full_name].present?

        # Only reset active/membership_status/payment_type if this is a new record
        if user.new_record?
          user.active = false
          user.membership_status = 'unknown'
          user.payment_type = 'unknown'
        end

        # Merge authentik_attributes - merge hashes instead of overwriting
        existing_attrs = user.authentik_attributes || {}
        new_attrs = attrs[:attributes] || {}
        user.authentik_attributes = existing_attrs.deep_merge(new_attrs)

        user.username = attrs[:username] if attrs[:username].present?

        user.last_synced_at = timestamp
        user.save!

        # Also update/create the AuthentikUser record
        sync_authentik_user(attrs, user, timestamp)

        # Create RFID record if present in attributes
        rfid_value = attrs[:attributes]&.dig('rfid')
        Rfid.find_or_create_by!(user: user, rfid: rfid_value.to_s) if rfid_value.present?
      rescue ActiveRecord::RecordInvalid => e
        @logger.error("Failed to sync Authentik user #{attrs.inspect}: #{e.message}")
      end
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

    def deactivate_missing_members(members)
      authentik_ids = members.pluck(:authentik_id).compact
      return if authentik_ids.empty?

      User.where.not(authentik_id: authentik_ids).where(active: true).update_all(
        active: false,
        membership_status: 'unknown',
        payment_type: 'unknown',
        updated_at: Time.current
      )
    end
  end
end
