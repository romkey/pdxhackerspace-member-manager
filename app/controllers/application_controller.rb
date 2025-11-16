class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception

  add_flash_types :success, :info

  helper_method :current_user, :user_signed_in?, :local_auth_enabled?, :authentik_enabled?

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

    redirect_to login_path, alert: "Please sign in to continue."
  end

  def local_auth_enabled?
    LocalAuthConfig.enabled?
  end

  def authentik_enabled?
    AuthentikConfig.enabled_for_login?
  end
end
