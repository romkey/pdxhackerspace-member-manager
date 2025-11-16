class SlackUsersController < AuthenticatedController
  def index
    @show_bots = ActiveModel::Type::Boolean.new.cast(params[:show_bots])
    scope = @show_bots ? SlackUser.all : SlackUser.where(is_bot: false)
    @slack_users = scope.order(:display_name, :real_name, :username)
    @total_slack_users = @slack_users.count
    user_emails = User.where.not(email: nil).pluck(:email)
    user_names = User.where.not(full_name: nil).pluck(:full_name)
    @shared_email_count = SlackUser.where(email: user_emails).count
    @shared_name_count = SlackUser.where(real_name: user_names).or(SlackUser.where(display_name: user_names)).count
  end

  def show
    @slack_user = SlackUser.find(params[:id])
    
    # Find previous and next users using the same ordering as index
    ordered_ids = SlackUser.order(:display_name, :real_name, :username).pluck(:id)
    current_index = ordered_ids.index(@slack_user.id)
    
    if current_index
      @previous_slack_user = current_index > 0 ? SlackUser.find(ordered_ids[current_index - 1]) : nil
      @next_slack_user = current_index < ordered_ids.length - 1 ? SlackUser.find(ordered_ids[current_index + 1]) : nil
    else
      @previous_slack_user = nil
      @next_slack_user = nil
    end
  end

  def sync
    Slack::UserSyncJob.perform_later
    redirect_to slack_users_path, notice: "Slack user sync started."
  end

  def sync_to_users
    linked_count = 0
    skipped_count = 0

    # Only process real users (not bots)
    SlackUser.where(is_bot: false).find_each do |slack_user|
      # Find matching users by full name (real_name)
      matches = []
      
      if slack_user.real_name.present?
        matches = User.where("LOWER(full_name) = ?", slack_user.real_name.downcase)
      end
      
      # Only link if exactly one match (do not create new users)
      if matches.count == 1
        user = matches.first
        
        # Link the slack user to the user
        slack_user.update!(user_id: user.id)
        
        # Handle email differences
        if slack_user.email.present?
          if user.email.blank?
            # User has no email, set it from slack user
            user.update!(email: slack_user.email)
          elsif user.email.downcase != slack_user.email.downcase
            # User has different email, add slack email to extra_emails
            extra_emails = user.extra_emails || []
            unless extra_emails.map(&:downcase).include?(slack_user.email.downcase)
              extra_emails << slack_user.email
              user.update!(extra_emails: extra_emails)
            end
          end
        end
        
        # Add slack_id and slack_handle to user (only if not already set)
        updates = {}
        updates[:slack_id] = slack_user.slack_id if user.slack_id.blank?
        updates[:slack_handle] = slack_user.username if user.slack_handle.blank?
        user.update!(updates) if updates.any?
        
        linked_count += 1
      else
        # No match or multiple matches, skip
        skipped_count += 1
      end
    end
    
    parts = []
    parts << "#{linked_count} linked" if linked_count > 0
    parts << "#{skipped_count} skipped" if skipped_count > 0
    
    notice = if parts.any?
               "Sync complete. #{parts.join(', ')}."
             else
               "Sync complete. No changes."
             end
    
    redirect_to slack_users_path, notice: notice
  end
end

