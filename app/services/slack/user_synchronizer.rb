module Slack
  class UserSynchronizer
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

      synced_ids.count
    end

    private

    def upsert_member(attrs)
      record = SlackUser.find_or_initialize_by(slack_id: attrs[:slack_id])
      record.assign_attributes(attrs)
      record.save!
      
      # Automatically link to User if there's a match (only for real users, not bots)
      if !attrs[:is_bot] && attrs[:real_name].present?
        link_to_user(record, attrs)
      end
    rescue ActiveRecord::RecordInvalid => e
      @logger.error("Failed to sync Slack user #{attrs[:slack_id]}: #{e.message}")
    end

    def link_to_user(slack_user, attrs)
      # Find matching users by full name (real_name)
      matches = User.where("LOWER(full_name) = ?", attrs[:real_name].downcase)
      
      # Only link if exactly one match
      if matches.count == 1
        user = matches.first
        
        # Link the slack user to the user
        slack_user.update!(user_id: user.id)
        
        # Handle email differences
        if attrs[:email].present?
          if user.email.blank?
            # User has no email, set it from slack user
            user.update!(email: attrs[:email])
          elsif user.email.downcase != attrs[:email].downcase
            # User has different email, add slack email to extra_emails
            extra_emails = user.extra_emails || []
            unless extra_emails.map(&:downcase).include?(attrs[:email].downcase)
              extra_emails << attrs[:email]
              user.update!(extra_emails: extra_emails)
            end
          end
        end
        
        # Add slack_id and slack_handle to user
        user.update!(
          slack_id: attrs[:slack_id],
          slack_handle: attrs[:username]
        )
      end
    end

    def deactivate_missing_members(synced_ids)
      return if synced_ids.empty?

      SlackUser.where.not(slack_id: synced_ids).where(deleted: false).update_all(deleted: true, updated_at: Time.current)
    end
  end
end

