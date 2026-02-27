class ProfileSetupController < AuthenticatedController
  before_action :set_user

  # Step 1: Basic Info
  def basic_info
  end

  def save_basic_info
    if @user.update(basic_info_params)
      redirect_to profile_setup_optional_path, status: :see_other
    else
      render :basic_info, status: :unprocessable_entity
    end
  end

  # Step 2: Optional Info (pronouns, bio, links)
  def optional_info
    @user_links = @user.user_links.ordered
  end

  def save_optional_info
    if @user.update(optional_info_params)
      redirect_to profile_setup_links_path, status: :see_other
    else
      @user_links = @user.user_links.ordered
      render :optional_info, status: :unprocessable_entity
    end
  end

  # Step 3: Profile Links
  def links
    @user_links = @user.user_links.ordered
  end

  # Step 4: Interests
  def interests
    @user_interests    = @user.interests.order(:name)
    @user_interest_ids = @user_interests.map(&:id).to_set
    @suggested         = Interest.suggested(limit: 20, exclude_ids: [])
  end

  def add_interest
    interest = Interest.find(params[:id])
    @user.interests << interest unless @user.interests.include?(interest)
    redirect_to profile_setup_interests_path, status: :see_other
  rescue ActiveRecord::RecordNotFound
    redirect_to profile_setup_interests_path, status: :see_other
  end

  def remove_interest
    interest = Interest.find(params[:id])
    @user.interests.delete(interest)
    redirect_to profile_setup_interests_path, status: :see_other
  rescue ActiveRecord::RecordNotFound
    redirect_to profile_setup_interests_path, status: :see_other
  end

  # Step 5: Visibility & Greeting (with preview)
  def visibility
  end

  def save_visibility
    attrs = visibility_params.to_h

    case params.dig(:user, :greeting_option)
    when 'full_name'
      attrs[:use_full_name_for_greeting] = true
      attrs[:use_username_for_greeting]  = false
      attrs[:do_not_greet]               = false
    when 'username'
      attrs[:use_full_name_for_greeting] = false
      attrs[:use_username_for_greeting]  = true
      attrs[:do_not_greet]               = false
    when 'custom'
      attrs[:use_full_name_for_greeting] = false
      attrs[:use_username_for_greeting]  = false
      attrs[:do_not_greet]               = false
      attrs[:greeting_name]              = params.dig(:user, :greeting_name).to_s.strip
    when 'do_not_greet'
      attrs[:use_full_name_for_greeting] = false
      attrs[:use_username_for_greeting]  = false
      attrs[:do_not_greet]               = true
      attrs[:greeting_name]              = ''
    end

    if @user.update(attrs)
      redirect_to user_path(@user), notice: 'Profile setup complete!', status: :see_other
    else
      render :visibility, status: :unprocessable_entity
    end
  end

  def add_link
    @user.user_links.create!(link_params)
    redirect_to profile_setup_links_path, status: :see_other
  rescue ActiveRecord::RecordInvalid
    redirect_to profile_setup_links_path, alert: 'Please provide both a title and URL for the link.'
  end

  def remove_link
    link = @user.user_links.find(params[:link_id])
    link.destroy!
    redirect_to profile_setup_links_path, status: :see_other
  end

  private

  def set_user
    @user = current_user
  end

  def basic_info_params
    params.require(:user).permit(:full_name, :email, :username)
  end

  def visibility_params
    params.require(:user).permit(:profile_visibility, :greeting_name)
  end

  def optional_info_params
    params.require(:user).permit(:pronouns, :bio)
  end

  def link_params
    params.require(:user_link).permit(:title, :url)
  end
end
