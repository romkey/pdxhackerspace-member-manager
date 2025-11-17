class SessionsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: :create

  def new
    return if authentik_enabled? || local_auth_enabled?

    render plain: "No authentication methods are configured.", status: :service_unavailable
  end

  def create
    auth = request.env["omniauth.auth"]
    user = upsert_user_from_auth(auth)
    user.update!(last_login_at: Time.current)
    session[:user_id] = user.id

    redirect_to root_path, notice: "Welcome back, #{user.display_name}!"
  rescue StandardError => e
    Rails.logger.error("Authentik sign-in failed: #{e.class} #{e.message}")
    redirect_to root_path, alert: "Unable to sign you in. Please try again."
  end

  def create_local
    unless local_auth_enabled?
      redirect_to login_path, alert: "Local authentication is disabled."
      return
    end

    account = find_local_account(session_params[:email])
    if account&.active? && account.authenticate(session_params[:password])
      account.touch(:last_signed_in_at)
      user = sync_local_account(account)
      user.update!(last_login_at: Time.current)
      session[:user_id] = user.id
      redirect_to root_path, notice: "Signed in locally as #{user.display_name}."
    else
      flash.now[:alert] = "Invalid email or password."
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    reset_session
    redirect_to root_path, notice: "Signed out successfully."
  end

  def create_rfid
    token = rfid_token

    if token.blank?
      redirect_to login_path, alert: "Please scan or enter an RFID value."
      return
    end

    user = find_user_by_rfid(token)

    if user
      user.update!(last_login_at: Time.current)
      session[:user_id] = user.id
      redirect_to root_path, notice: "Signed in via RFID as #{user.display_name}."
    else
      redirect_to login_path, alert: "No user with that RFID was found."
    end
  end

  def failure
    redirect_to root_path, alert: params[:message] || "Authentication failed."
  end

  private

  def upsert_user_from_auth(auth)
    payload = auth&.respond_to?(:deep_symbolize_keys) ? auth.deep_symbolize_keys : {}
    info = payload.fetch(:info, {})
    extra = payload.fetch(:extra, {}).fetch(:raw_info, {})

    attributes = {
      email: info[:email] || extra[:email],
      full_name: info[:name] || build_full_name(info, extra),
      membership_status: "active",
      last_synced_at: Time.current
    }

    User.find_or_initialize_by(authentik_id: payload[:uid].to_s).tap do |user|
      user.assign_attributes(attributes.compact)
      user.save!
    end
  end

  def sync_local_account(account)
    User.find_or_initialize_by(authentik_id: "local:#{account.id}").tap do |user|
      user.assign_attributes(
        email: account.email,
        full_name: account.full_name,
        membership_status: account.active ? "active" : "inactive",
        last_synced_at: Time.current
      )
      user.save!
    end
  end

  def session_params
    params.require(:session).permit(:email, :password)
  end

  def rfid_params
    params.require(:rfid).permit(:token)
  end

  def rfid_token
    rfid_params[:token]
  rescue ActionController::ParameterMissing
    nil
  end

  def find_local_account(email)
    normalized_email = email.to_s.strip.downcase
    return if normalized_email.blank?

    LocalAccount.find_by("LOWER(email) = ?", normalized_email)
  end

  def build_full_name(info, extra)
    parts = [
      info[:first_name],
      info[:last_name],
      extra[:first_name],
      extra[:last_name]
    ].compact_blank

    parts.presence&.join(" ")
  end

  def find_user_by_rfid(value)
    normalized = value.to_s.strip.downcase
    return if normalized.blank?

    # Search in the rfid array column
    User.active.where("EXISTS (SELECT 1 FROM unnest(rfid) AS r WHERE LOWER(r) = ?)", normalized).first
  end
end

