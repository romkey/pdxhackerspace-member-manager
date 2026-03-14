class LoginLinksController < ApplicationController
  before_action :require_authenticated_user!, only: %i[show regenerate]

  def show
    @user = current_user
  end

  def regenerate
    current_user.generate_login_token!
    redirect_to login_link_path, notice: 'Login link generated successfully.'
  end

  def request_link
    identifier = params[:identifier].to_s.strip
    if identifier.blank?
      redirect_to login_path, alert: 'Please enter your email or username.'
      return
    end

    user = User.find_by('LOWER(email) = ?', identifier.downcase) ||
           User.find_by('LOWER(username) = ?', identifier.downcase)

    if user
      user.generate_login_token!
      QueuedMail.enqueue('login_link_sent', user,
                         login_url: login_link_authenticate_url(token: user.login_token))
    end

    redirect_to login_path,
                notice: 'If an account exists with that email or username, a login link has been sent.'
  end

  def authenticate
    user = User.find_by(login_token: params[:token])

    if user.nil?
      redirect_to login_path, alert: 'Invalid or already-used login link.'
      return
    end

    if user.login_token_expired?
      user.clear_login_token!
      QueuedMail.enqueue('login_link_expired', user, reason: 'Login link expired')
      redirect_to login_path, alert: 'This login link has expired. Please request a new one.'
      return
    end

    user.update!(last_login_at: Time.current)
    user.clear_login_token!
    session[:user_id] = user.id
    redirect_to root_path, notice: "Welcome back, #{user.display_name}!"
  end

  private

  def require_authenticated_user!
    return if user_signed_in?

    redirect_to login_path, alert: 'Please sign in to continue.'
  end
end
