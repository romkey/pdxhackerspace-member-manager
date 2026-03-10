class LoginLinksController < ApplicationController
  before_action :require_authenticated_user!, only: %i[show regenerate]

  def show
    @user = current_user
  end

  def regenerate
    current_user.generate_login_token!
    redirect_to login_link_path, notice: 'Login link generated successfully.'
  end

  def authenticate
    user = User.find_by(login_token: params[:token])

    if user.nil?
      redirect_to login_path, alert: 'Invalid login link.'
      return
    end

    if user.login_token_expired?
      user.clear_login_token!
      QueuedMail.enqueue('login_link_expired', user, reason: 'Login link expired')
      redirect_to login_path, alert: 'This login link has expired. Please sign in and generate a new one.'
      return
    end

    user.update!(last_login_at: Time.current)
    session[:user_id] = user.id
    redirect_to root_path, notice: "Welcome back, #{user.display_name}!"
  end

  private

  def require_authenticated_user!
    return if user_signed_in?

    redirect_to login_path, alert: 'Please sign in to continue.'
  end
end
