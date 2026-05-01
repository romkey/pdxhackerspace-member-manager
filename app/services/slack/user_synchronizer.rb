module Slack
  class UserSynchronizer
    include UserNameMatcher

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

      # Record sync in member source
      MemberSource.for('slack').record_sync!

      synced_ids.count
    end

    private

    def upsert_member(attrs)
      record = SlackUser.find_or_initialize_by(slack_id: attrs[:slack_id])
      record.assign_attributes(attrs)
      record.save!

      # Automatically link to User if there's a match (only for real users, not bots)
      link_to_user(record, attrs) if !attrs[:is_bot] && attrs[:real_name].present?
    rescue ActiveRecord::RecordInvalid => e
      @logger.error("Failed to sync Slack user #{attrs[:slack_id]}: #{e.message}")
    end

    def link_to_user(slack_user, attrs)
      # Find matching users by email or full name (real_name)
      matches = []

      # Match by email (case-insensitive)
      if attrs[:email].present?
        normalized_email = attrs[:email].to_s.strip.downcase
        # Match by primary email
        matches += User.where('LOWER(email) = ?', normalized_email)
        # Match by extra_emails array (case-insensitive)
        matches += User.where('EXISTS (SELECT 1 FROM unnest(extra_emails) AS email WHERE LOWER(email) = ?)',
                              normalized_email)
      end

      # Match by full name or alias (real_name)
      matches += User.by_name_or_alias(attrs[:real_name]) if attrs[:real_name].present?

      # Remove duplicates
      matches = matches.uniq

      # Only link if exactly one match
      return unless matches.one?

      user = matches.first

      # Link the slack user to the user
      slack_user.update!(user_id: user.id)
    end

    def deactivate_missing_members(synced_ids)
      return if synced_ids.empty?

      SlackUser.where.not(slack_id: synced_ids).where(deleted: false).update_all(deleted: true,
                                                                                 updated_at: Time.current)
    end
  end
end
