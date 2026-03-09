class ProfileSetupController < AuthenticatedController
  before_action :set_user

  # Step 1: Basic Info
  def basic_info; end

  def save_basic_info
    if @user.update(basic_info_params)
      redirect_to profile_setup_optional_path, status: :see_other
    else
      render :basic_info, status: :unprocessable_content
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
      render :optional_info, status: :unprocessable_content
    end
  end

  # Step 3: Profile Links
  def links
    @user_links = @user.user_links.ordered
  end

  # Step 4: Interests
  def interests
    @user_interests    = @user.interests.order(:name)
    @user_interest_ids = @user_interests.to_set(&:id)
    @suggested         = Interest.suggested(limit: 20, exclude_ids: [])
    @all_interests     = Interest.alphabetical.pluck(:id, :name).map { |id, name| { id: id, name: name } }
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

  def suggest_interest
    name = params[:interest_name].to_s.strip
    if name.blank?
      redirect_to profile_setup_interests_path, alert: 'Please enter an interest name.'
      return
    end

    interest = Interest.find_by('LOWER(name) = ?', name.downcase)
    interest = Interest.create!(name: name, needs_review: true, seeded: false) if interest.nil?

    @user.interests << interest unless @user.interests.include?(interest)
    notice = "'#{interest.name}' added to your profile."
    redirect_to profile_setup_interests_path, notice: notice, status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_to profile_setup_interests_path, alert: "Couldn't add interest: #{e.message}", status: :see_other
  end

  # Step 5: Visibility & Greeting (with preview)
  def visibility; end

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
      render :visibility, status: :unprocessable_content
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
    params.expect(user: %i[full_name email username])
  end

  def visibility_params
    params.expect(user: %i[profile_visibility greeting_name])
  end

  def optional_info_params
    params.expect(user: %i[pronouns bio])
  end

  def link_params
    params.expect(user_link: %i[title url])
  end
end
