class ApplicationController < ActionController::Base
  include Pagy::Backend

  protect_from_forgery with: :exception

  add_flash_types :success, :info

  helper_method :current_user, :user_signed_in?, :local_auth_enabled?, :authentik_enabled?, 
                :current_user_admin?, :true_user_admin?, :pagy_nav, :impersonating?, :true_user

  private

  def current_user
    return @current_user if defined?(@current_user)

    # If impersonating, return the impersonated user
    if session[:impersonated_user_id].present?
      @current_user = User.find_by(id: session[:impersonated_user_id])
    else
      @current_user = User.find_by(id: session[:user_id])
    end
  end

  # The actual logged-in admin (even when impersonating)
  def true_user
    return @true_user if defined?(@true_user)

    @true_user = User.find_by(id: session[:user_id])
  end

  before_action do
    Current.user = current_user
  end

  def user_signed_in?
    current_user.present?
  end

  # Check if currently impersonating another user
  def impersonating?
    session[:impersonated_user_id].present?
  end

  def require_authenticated_user!
    return if user_signed_in?

    redirect_to login_path, alert: 'Please sign in to continue.'
  end

  def local_auth_enabled?
    LocalAuthConfig.enabled?
  end

  def authentik_enabled?
    AuthentikConfig.enabled_for_login?
  end

  def current_user_admin?
    # For display/view purposes, check the current_user (impersonated user if active)
    # This shows what the impersonated user would see
    current_user&.is_admin?
  end

  # Check if the actual logged-in user is an admin (ignores impersonation)
  def true_user_admin?
    true_user&.is_admin?
  end

  def require_admin!
    # Always check true_user for admin access (can't bypass by impersonating an admin)
    return if true_user&.is_admin?

    if current_user
      redirect_to user_path(current_user), alert: 'You do not have access to that section.'
    else
      redirect_to login_path, alert: 'Admin access is required to proceed.'
    end
  end
end
