require 'csv'

class SlackUsersController < AdminController
  SORTABLE_COLUMNS = %w[display_name email is_admin is_owner is_bot deleted].freeze

  def index
    # Start with all slack users for counts (before filtering)
    all_slack_users = SlackUser.all
    
    # Calculate counts from ALL slack users (not filtered)
    @total_count = all_slack_users.count
    @linked_count = all_slack_users.where.not(user_id: nil).count
    @unlinked_count = @total_count - @linked_count
    @admin_count = all_slack_users.where(is_admin: true).count
    @owner_count = all_slack_users.where(is_owner: true).count
    @bot_count = all_slack_users.where(is_bot: true).count
    @human_count = all_slack_users.where(is_bot: false).count
    @active_count = all_slack_users.where(deleted: false).count
    @deactivated_count = all_slack_users.where(deleted: true).count
    
    # Now build filtered query
    @slack_users = all_slack_users.includes(:user)
    
    # Apply filters
    case params[:linked]
    when 'yes'
      @slack_users = @slack_users.where.not(user_id: nil)
    when 'no'
      @slack_users = @slack_users.where(user_id: nil)
    end
    
    @slack_users = @slack_users.where(is_admin: true) if params[:is_admin] == 'yes'
    @slack_users = @slack_users.where(is_admin: false) if params[:is_admin] == 'no'
    @slack_users = @slack_users.where(is_owner: true) if params[:is_owner] == 'yes'
    @slack_users = @slack_users.where(is_owner: false) if params[:is_owner] == 'no'
    @slack_users = @slack_users.where(is_bot: true) if params[:is_bot] == 'yes'
    @slack_users = @slack_users.where(is_bot: false) if params[:is_bot] == 'no'
    @slack_users = @slack_users.where(deleted: false) if params[:status] == 'active'
    @slack_users = @slack_users.where(deleted: true) if params[:status] == 'deactivated'
    
    # Apply sorting
    @sort_column = SORTABLE_COLUMNS.include?(params[:sort]) ? params[:sort] : 'display_name'
    @sort_direction = %w[asc desc].include?(params[:direction]) ? params[:direction] : 'asc'
    @slack_users = @slack_users.order("#{@sort_column} #{@sort_direction} NULLS LAST")
    
    # Track if any filter is active
    @filter_active = params[:linked].present? || params[:is_admin].present? || 
                     params[:is_owner].present? || params[:is_bot].present? || params[:status].present?
    @filtered_count = @slack_users.count if @filter_active
    
    # Store filter/sort params for links
    @list_params = {}
    @list_params[:linked] = params[:linked] if params[:linked].present?
    @list_params[:is_admin] = params[:is_admin] if params[:is_admin].present?
    @list_params[:is_owner] = params[:is_owner] if params[:is_owner].present?
    @list_params[:is_bot] = params[:is_bot] if params[:is_bot].present?
    @list_params[:status] = params[:status] if params[:status].present?
    @list_params[:sort] = params[:sort] if params[:sort].present?
    @list_params[:direction] = params[:direction] if params[:direction].present?
  end

  def show
    @slack_user = SlackUser.includes(:user).find(params[:id])

    # Get all users for the selection dropdown (if no match found)
    @all_users = User.ordered_by_display_name if @slack_user.user.nil?

    # Rebuild the same filtered/sorted query from the index page
    nav_query = SlackUser.all
    
    # Apply filters if present
    case params[:linked]
    when 'yes'
      nav_query = nav_query.where.not(user_id: nil)
    when 'no'
      nav_query = nav_query.where(user_id: nil)
    end
    
    nav_query = nav_query.where(is_admin: true) if params[:is_admin] == 'yes'
    nav_query = nav_query.where(is_admin: false) if params[:is_admin] == 'no'
    nav_query = nav_query.where(is_owner: true) if params[:is_owner] == 'yes'
    nav_query = nav_query.where(is_owner: false) if params[:is_owner] == 'no'
    nav_query = nav_query.where(is_bot: true) if params[:is_bot] == 'yes'
    nav_query = nav_query.where(is_bot: false) if params[:is_bot] == 'no'
    nav_query = nav_query.where(deleted: false) if params[:status] == 'active'
    nav_query = nav_query.where(deleted: true) if params[:status] == 'deactivated'
    
    # Apply sorting
    sort_column = SORTABLE_COLUMNS.include?(params[:sort]) ? params[:sort] : 'display_name'
    sort_direction = %w[asc desc].include?(params[:direction]) ? params[:direction] : 'asc'
    nav_query = nav_query.order("#{sort_column} #{sort_direction} NULLS LAST")
    
    ordered_ids = nav_query.pluck(:id)
    current_index = ordered_ids.index(@slack_user.id)

    if current_index
      @previous_slack_user = current_index.positive? ? SlackUser.find(ordered_ids[current_index - 1]) : nil
      @next_slack_user = current_index < ordered_ids.length - 1 ? SlackUser.find(ordered_ids[current_index + 1]) : nil
    else
      @previous_slack_user = nil
      @next_slack_user = nil
    end
    
    # Store filter/sort params for use in view links
    @nav_params = {}
    @nav_params[:linked] = params[:linked] if params[:linked].present?
    @nav_params[:is_admin] = params[:is_admin] if params[:is_admin].present?
    @nav_params[:is_owner] = params[:is_owner] if params[:is_owner].present?
    @nav_params[:is_bot] = params[:is_bot] if params[:is_bot].present?
    @nav_params[:status] = params[:status] if params[:status].present?
    @nav_params[:sort] = params[:sort] if params[:sort].present?
    @nav_params[:direction] = params[:direction] if params[:direction].present?
  end

  def link_user
    @slack_user = SlackUser.find(params[:id])
    user = User.find(params[:user_id])

    # Link the slack user to the user
    @slack_user.update!(user_id: user.id)

    # Prepare user updates
    updates = {}

    # Handle email - if User doesn't have an email, copy it from Slack user
    if @slack_user.email.present?
      if user.email.blank?
        # User has no email, set it from slack user
        updates[:email] = @slack_user.email
      elsif user.email.downcase != @slack_user.email.downcase
        # User has different email, add slack email to extra_emails
        extra_emails = user.extra_emails || []
        unless extra_emails.map(&:downcase).include?(@slack_user.email.downcase)
          extra_emails << @slack_user.email
          updates[:extra_emails] = extra_emails
        end
      end
    end

    # Add slack_id and slack_handle to user (only if not already set)
    updates[:slack_id] = @slack_user.slack_id if user.slack_id.blank?
    updates[:slack_handle] = @slack_user.username if user.slack_handle.blank?

    # Set avatar from Slack profile image_192 if image_original exists (indicating a custom image)
    if @slack_user.raw_attributes.dig('profile', 'image_original').present?
      image_192_url = @slack_user.raw_attributes.dig('profile', 'image_192')
      updates[:avatar] = image_192_url if image_192_url.present?
    end

    # Apply all updates at once
    user.update!(updates) if updates.any?

    redirect_to slack_user_path(@slack_user),
                notice: "Linked to user #{user.display_name} and updated their Slack information."
  end

  def sync
    Slack::UserSyncJob.perform_later
    redirect_to slack_users_path, notice: 'Slack user sync started.'
  end

  def sync_to_users
    linked_count = 0
    skipped_count = 0

    # Only process real users (not bots)
    SlackUser.where(is_bot: false).find_each do |slack_user|
      # Find matching users by email or full name (real_name)
      matches = []

      # Match by email (case-insensitive)
      if slack_user.email.present?
        normalized_email = slack_user.email.to_s.strip.downcase
        # Match by primary email
        matches += User.where('LOWER(email) = ?', normalized_email)
        # Match by extra_emails array (case-insensitive)
        matches += User.where('EXISTS (SELECT 1 FROM unnest(extra_emails) AS email WHERE LOWER(email) = ?)',
                              normalized_email)
      end

      # Match by full name (real_name)
      if slack_user.real_name.present?
        matches += User.where('LOWER(full_name) = ?', slack_user.real_name.downcase)
      end

      # Remove duplicates
      matches = matches.uniq

      # Only link if exactly one match (do not create new users)
      if matches.one?
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

        # Set avatar from Slack profile image_192 if image_original exists (indicating a custom image)
        if slack_user.raw_attributes.dig('profile', 'image_original').present?
          image_192_url = slack_user.raw_attributes.dig('profile', 'image_192')
          updates[:avatar] = image_192_url if image_192_url.present?
        end

        user.update!(updates) if updates.any?

        linked_count += 1
      else
        # No match or multiple matches, skip
        skipped_count += 1
      end
    end

    parts = []
    parts << "#{linked_count} linked" if linked_count.positive?
    parts << "#{skipped_count} skipped" if skipped_count.positive?

    notice = if parts.any?
               "Sync complete. #{parts.join(', ')}."
             else
               'Sync complete. No changes.'
             end

    redirect_to slack_users_path, notice: notice
  end

  def import_members
    if params[:file].blank?
      redirect_to slack_users_path, alert: 'Please choose a CSV file to import.'
      return
    end

    counts = Slack::CsvMemberImporter.new.call(params[:file])

    parts = []
    parts << "#{counts[:imported]} imported"
    parts << "#{counts[:updated]} updated"
    parts << "#{counts[:skipped]} skipped" if counts[:skipped].positive?

    redirect_to slack_users_path, notice: "Import complete: #{parts.join(', ')}."
  rescue CSV::MalformedCSVError => e
    redirect_to slack_users_path, alert: "Invalid CSV: #{e.message}"
  end

  def import_analytics
    if params[:file].blank?
      redirect_to slack_users_path, alert: 'Please choose a CSV file to import.'
      return
    end

    counts = Slack::CsvAnalyticsImporter.new.call(params[:file])

    parts = []
    parts << "#{counts[:updated]} updated"
    parts << "#{counts[:skipped]} skipped" if counts[:skipped].positive?

    redirect_to slack_users_path, notice: "Analytics import complete: #{parts.join(', ')}."
  rescue CSV::MalformedCSVError => e
    redirect_to slack_users_path, alert: "Invalid CSV: #{e.message}"
  end
end
