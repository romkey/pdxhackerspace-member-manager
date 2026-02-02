class UserLinksController < AuthenticatedController
  before_action :set_user
  before_action :authorize_self_or_admin
  before_action :set_user_link, only: [:update, :destroy]

  def create
    @user_link = @user.user_links.build(user_link_params)
    @user_link.position = @user.user_links.maximum(:position).to_i + 1

    if @user_link.save
      redirect_to edit_user_path(@user, anchor: 'links'), notice: 'Link added successfully.'
    else
      redirect_to edit_user_path(@user, anchor: 'links'), alert: "Could not add link: #{@user_link.errors.full_messages.join(', ')}"
    end
  end

  def update
    if @user_link.update(user_link_params)
      redirect_to edit_user_path(@user, anchor: 'links'), notice: 'Link updated successfully.'
    else
      redirect_to edit_user_path(@user, anchor: 'links'), alert: "Could not update link: #{@user_link.errors.full_messages.join(', ')}"
    end
  end

  def destroy
    @user_link.destroy
    redirect_to edit_user_path(@user, anchor: 'links'), notice: 'Link removed.'
  end

  private

  def set_user
    @user = User.find_by_param(params[:user_id])
  end

  def set_user_link
    @user_link = @user.user_links.find(params[:id])
  end

  def authorize_self_or_admin
    return if current_user_admin?
    return if @user == current_user

    redirect_to user_path(current_user), alert: 'You may only edit your own profile.'
  end

  def user_link_params
    params.require(:user_link).permit(:title, :url)
  end
end
