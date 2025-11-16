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

      members.count
    end

    private

    def upsert_members(members, timestamp)
      members.each do |attrs|
        user = User.find_or_initialize_by(authentik_id: attrs[:authentik_id])
        user.assign_attributes(
          email: attrs[:email],
          full_name: attrs[:full_name],
          active: attrs.fetch(:active, true),
          authentik_attributes: attrs[:attributes] || {},
          last_synced_at: timestamp
        )
        user.save!
      rescue ActiveRecord::RecordInvalid => e
        @logger.error("Failed to sync Authentik user #{attrs.inspect}: #{e.message}")
      end
    end

    def deactivate_missing_members(members)
      authentik_ids = members.map { |attrs| attrs[:authentik_id] }.compact
      return if authentik_ids.empty?

      User.where.not(authentik_id: authentik_ids).where(active: true).update_all(active: false, updated_at: Time.current)
    end
  end
end


