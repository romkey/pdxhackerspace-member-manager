class ApplicationGroupsController < AdminController
  before_action :set_application
  before_action :set_application_group, only: %i[show edit update destroy add_user remove_user sync_to_authentik]

  def show
    @users = @application_group.effective_members.merge(User.ordered_by_display_name)
    @all_users = User.ordered_by_display_name
    @unsyncable_members = @application_group.unsyncable_members
  end

  def new
    @application_group = @application.application_groups.build
    @training_topics = TrainingTopic.order(:name)
    @default_settings = DefaultSetting.instance
    
    if @application.authentik_prefix.present?
      @application_group.authentik_name = "#{@application.authentik_prefix}:"
    else
      @application_group.authentik_name = "#{@default_settings.app_prefix}:"
    end
  end

  def edit
    @training_topics = TrainingTopic.order(:name)
    @default_settings = DefaultSetting.instance
  end

  def create
    @application_group = @application.application_groups.build(application_group_params)
    ensure_mutual_exclusivity(@application_group)
    set_authentik_name_from_checkboxes(@application_group)

    if @application_group.save
      # Create group in Authentik
      sync_result = sync_group_to_authentik(@application_group)
      notice = build_sync_notice('Application group created successfully.', sync_result)

      redirect_to application_application_group_path(@application, @application_group), notice: notice
    else
      @training_topics = TrainingTopic.order(:name)
      @default_settings = DefaultSetting.instance
      flash.now[:alert] = 'Unable to create application group.'
      render :new, status: :unprocessable_content
    end
  end

  def update
    @application_group.assign_attributes(application_group_params)
    ensure_mutual_exclusivity(@application_group)
    set_authentik_name_from_checkboxes(@application_group)

    if @application_group.save
      # Sync to Authentik
      sync_result = sync_group_to_authentik(@application_group)
      notice = build_sync_notice('Application group updated successfully.', sync_result)

      redirect_to application_application_group_path(@application, @application_group), notice: notice
    else
      @training_topics = TrainingTopic.order(:name)
      @default_settings = DefaultSetting.instance
      flash.now[:alert] = 'Unable to update application group.'
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    group_name = @application_group.name

    # Delete from Authentik first
    if @application_group.authentik_group_id.present?
      begin
        sync = Authentik::GroupSync.new(@application_group)
        sync.delete!
      rescue StandardError => e
        Rails.logger.error("[ApplicationGroupsController] Failed to delete group from Authentik: #{e.message}")
      end
    end

    @application_group.destroy
    redirect_to application_path(@application), notice: "Application group '#{group_name}' deleted."
  end

  def add_user
    if @application_group.uses_default_group?
      redirect_to application_application_group_path(@application, @application_group),
                  alert: 'Cannot add users to a group that uses a default group.'
      return
    end

    user = User.find(params[:user_id])

    if @application_group.users.include?(user)
      redirect_to application_application_group_path(@application, @application_group),
                  alert: 'User is already in this group.'
    else
      @application_group.users << user

      # Sync membership to Authentik
      sync_result = sync_group_members(@application_group)
      notice = build_sync_notice('User added to group.', sync_result)

      redirect_to application_application_group_path(@application, @application_group), notice: notice
    end
  end

  def remove_user
    if @application_group.uses_default_group?
      redirect_to application_application_group_path(@application, @application_group),
                  alert: 'Cannot remove users from a group that uses a default group.'
      return
    end

    user = User.find(params[:user_id])
    @application_group.users.delete(user)

    # Sync membership to Authentik
    sync_result = sync_group_members(@application_group)
    notice = build_sync_notice('User removed from group.', sync_result)

    redirect_to application_application_group_path(@application, @application_group), notice: notice
  end

  def sync_to_authentik
    sync_result = sync_group_to_authentik(@application_group)

    if sync_result[:status] == 'error'
      redirect_to application_application_group_path(@application, @application_group),
                  alert: "Sync failed: #{sync_result[:error]}"
    else
      notice = build_sync_notice('Group synced to Authentik.', sync_result)
      redirect_to application_application_group_path(@application, @application_group), notice: notice
    end
  end

  private

  def set_application
    @application = Application.find(params[:application_id])
  end

  def set_application_group
    @application_group = @application.application_groups.find(params[:id])
  end

  def application_group_params
    params.require(:application_group).permit(:name, :authentik_name, :authentik_group_id, :note, :use_default_members_group, :use_default_admins_group, :use_can_train, :use_trained_in, :training_topic_id)
  end

  def ensure_mutual_exclusivity(group)
    # Get which option was just set
    params_hash = params[:application_group] || {}
    
    if params_hash[:use_default_members_group] == '1'
      group.use_default_admins_group = false
      group.use_can_train = false
      group.use_trained_in = false
    elsif params_hash[:use_default_admins_group] == '1'
      group.use_default_members_group = false
      group.use_can_train = false
      group.use_trained_in = false
    elsif params_hash[:use_can_train] == '1'
      group.use_default_members_group = false
      group.use_default_admins_group = false
      group.use_trained_in = false
    elsif params_hash[:use_trained_in] == '1'
      group.use_default_members_group = false
      group.use_default_admins_group = false
      group.use_can_train = false
    end
  end

  def set_authentik_name_from_checkboxes(group)
    defaults = DefaultSetting.instance
    
    if group.use_default_members_group?
      group.authentik_name = defaults.active_members_group
    elsif group.use_default_admins_group?
      group.authentik_name = defaults.admins_group
    elsif group.use_can_train? && group.training_topic
      topic_slug = group.training_topic.name.downcase.gsub(/\s+/, '-')
      group.authentik_name = "#{defaults.can_train_prefix}:#{topic_slug}"
    elsif group.use_trained_in? && group.training_topic
      topic_slug = group.training_topic.name.downcase.gsub(/\s+/, '-')
      group.authentik_name = "#{defaults.trained_on_prefix}:#{topic_slug}"
    end
  end

  def sync_group_to_authentik(group)
    return { status: 'skipped', reason: 'api_not_configured' } unless authentik_api_configured?

    sync = Authentik::GroupSync.new(group)
    sync.sync!
  rescue StandardError => e
    Rails.logger.error("[ApplicationGroupsController] Authentik sync failed: #{e.message}")
    { status: 'error', error: e.message }
  end

  def sync_group_members(group)
    return { status: 'skipped', reason: 'no_authentik_group_id' } if group.authentik_group_id.blank?
    return { status: 'skipped', reason: 'api_not_configured' } unless authentik_api_configured?

    sync = Authentik::GroupSync.new(group)
    sync.sync_members!
  rescue StandardError => e
    Rails.logger.error("[ApplicationGroupsController] Authentik member sync failed: #{e.message}")
    { status: 'error', error: e.message }
  end

  def authentik_api_configured?
    AuthentikConfig.settings.api_token.present? && AuthentikConfig.settings.api_base_url.present?
  end

  def build_sync_notice(base_message, sync_result)
    return base_message if sync_result.nil?

    case sync_result[:status]
    when 'created'
      "#{base_message} Group created in Authentik."
    when 'exists'
      "#{base_message} Linked to existing Authentik group."
    when 'updated', 'synced'
      members_info = sync_result[:members] || sync_result
      if members_info[:added].to_i > 0 || members_info[:removed].to_i > 0
        "#{base_message} Authentik sync: +#{members_info[:added]} / -#{members_info[:removed]} members."
      else
        "#{base_message} Synced to Authentik."
      end
    when 'skipped'
      base_message
    when 'error'
      "#{base_message} Warning: Authentik sync failed - #{sync_result[:error]}"
    else
      base_message
    end
  end
end
