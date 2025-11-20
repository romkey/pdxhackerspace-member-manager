class ApplicationGroupsController < AuthenticatedController
  before_action :set_application
  before_action :set_application_group, only: %i[show edit update add_user remove_user]

  def show
    @users = @application_group.users.merge(User.ordered_by_display_name)
    @all_users = User.ordered_by_display_name
  end

  def new
    @application_group = @application.application_groups.build
    return if @application.authentik_prefix.blank?

    @application_group.authentik_name = "#{@application.authentik_prefix}:"
  end

  def edit; end

  def create
    @application_group = @application.application_groups.build(application_group_params)

    if @application_group.save
      redirect_to application_application_group_path(@application, @application_group),
                  notice: 'Application group created successfully.'
    else
      flash.now[:alert] = 'Unable to create application group.'
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @application_group.update(application_group_params)
      redirect_to application_application_group_path(@application, @application_group),
                  notice: 'Application group updated successfully.'
    else
      flash.now[:alert] = 'Unable to update application group.'
      render :edit, status: :unprocessable_content
    end
  end

  def add_user
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
    params.require(:application_group).permit(:name, :authentik_name, :note)
  end
end
