class ApplicationController < ActionController::Base
  include Pagy::Backend

  protect_from_forgery with: :exception

  add_flash_types :success, :info

  helper_method :current_user, :user_signed_in?, :local_auth_enabled?, :authentik_enabled?, :current_user_admin?, :pagy_nav

  private

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = User.find_by(id: session[:user_id])
  end

  before_action do
    Current.user = current_user
  end

  def user_signed_in?
    current_user.present?
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
    current_user&.is_admin?
  end

  def require_admin!
    return if current_user_admin?

    if current_user
      redirect_to user_path(current_user), alert: 'You do not have access to that section.'
    else
      redirect_to login_path, alert: 'Admin access is required to proceed.'
    end
  end
end
