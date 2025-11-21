class ApplicationGroupsController < AuthenticatedController
  before_action :set_application
  before_action :set_application_group, only: %i[show edit update add_user remove_user]

  def show
    @users = @application_group.users.merge(User.ordered_by_display_name)
    @all_users = User.ordered_by_display_name
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
      redirect_to application_application_group_path(@application, @application_group),
                  notice: 'Application group created successfully.'
    else
      flash.now[:alert] = 'Unable to create application group.'
      render :new, status: :unprocessable_content
    end
  end

  def update
    @application_group.assign_attributes(application_group_params)
    ensure_mutual_exclusivity(@application_group)
    set_authentik_name_from_checkboxes(@application_group)

    if @application_group.save
      redirect_to application_application_group_path(@application, @application_group),
                  notice: 'Application group updated successfully.'
    else
      flash.now[:alert] = 'Unable to update application group.'
      render :edit, status: :unprocessable_content
    end
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
      redirect_to application_application_group_path(@application, @application_group), notice: 'User added to group.'
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
    redirect_to application_application_group_path(@application, @application_group), notice: 'User removed from group.'
  end

  private

  def set_application
    @application = Application.find(params[:application_id])
  end

  def set_application_group
    @application_group = @application.application_groups.find(params[:id])
  end

  def application_group_params
    params.require(:application_group).permit(:name, :authentik_name, :note, :use_default_members_group, :use_default_admins_group, :use_can_train, :use_trained_in, :training_topic_id)
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
end
