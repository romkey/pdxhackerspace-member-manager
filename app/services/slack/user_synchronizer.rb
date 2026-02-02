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

      # Match by full name (real_name)
      if attrs[:real_name].present?
        matches += User.where('LOWER(full_name) = ?', attrs[:real_name].downcase)
      end

      # Remove duplicates
      matches = matches.uniq

      # Only link if exactly one match
      return unless matches.one?

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

      # Add slack_id and slack_handle to user (only if not already set)
      updates = {}
      updates[:slack_id] = attrs[:slack_id] if user.slack_id.blank?
      updates[:slack_handle] = attrs[:username] if user.slack_handle.blank?

      # Sync pronouns from Slack if user doesn't have pronouns set
      if attrs[:pronouns].present? && user.pronouns.blank?
        updates[:pronouns] = attrs[:pronouns]
      end

      # Set avatar from Slack profile image_192 if image_original exists (indicating a custom image)
      profile = attrs[:raw_attributes]&.dig('profile') || {}
      if profile['image_original'].present?
        image_192_url = profile['image_192']
        updates[:avatar] = image_192_url if image_192_url.present?
      end

      # Sync bio from Slack title field if user doesn't have bio set
      if attrs[:title].present? && user.bio.blank?
        updates[:bio] = attrs[:title]
      end

      user.update!(updates) if updates.any?

      # Sync profile links from Slack custom fields if available
      sync_profile_links(user, profile)
    end

    def deactivate_missing_members(synced_ids)
      return if synced_ids.empty?

      SlackUser.where.not(slack_id: synced_ids).where(deleted: false).update_all(deleted: true,
                                                                                 updated_at: Time.current)
    end

    def sync_profile_links(user, profile)
      return if user.user_links.any? # Don't overwrite existing links

      links_to_create = []

      # Check for common profile fields that might contain URLs
      fields = profile['fields'] || {}
      fields.each do |_field_id, field_data|
        next unless field_data.is_a?(Hash)

        value = field_data['value'].to_s.strip
        label = field_data['label'].to_s.strip

        # Check if value looks like a URL
        next unless value.match?(%r{^https?://})

        # Determine title from label or URL
        title = label.presence || extract_title_from_url(value)
        links_to_create << { title: title, url: value }
      end

      # Create links if we found any
      links_to_create.each_with_index do |link_attrs, index|
        user.user_links.create!(
          title: link_attrs[:title],
          url: link_attrs[:url],
          position: index
        )
      rescue ActiveRecord::RecordInvalid => e
        @logger.warn("Failed to create user link for #{user.id}: #{e.message}")
      end
    end

    def extract_title_from_url(url)
      case url.downcase
      when /github\.com/
        'GitHub'
      when /linkedin\.com/
        'LinkedIn'
      when /twitter\.com|x\.com/
        'Twitter/X'
      when /instagram\.com/
        'Instagram'
      when /facebook\.com/
        'Facebook'
      when /youtube\.com/
        'YouTube'
      when /mastodon|hachyderm|fosstodon/
        'Mastodon'
      when /gitlab\.com/
        'GitLab'
      else
        'Website'
      end
    end
  end
end
