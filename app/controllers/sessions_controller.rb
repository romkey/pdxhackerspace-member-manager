class SessionsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: :create

  def new
    return if authentik_enabled? || local_auth_enabled?

    render plain: 'No authentication methods are configured.', status: :service_unavailable
  end

  def create
    auth = request.env['omniauth.auth']
    user = upsert_user_from_auth(auth)
    user.update!(last_login_at: Time.current)
    session[:user_id] = user.id

    redirect_to root_path, notice: "Welcome back, #{user.display_name}!"
  rescue StandardError => e
    Rails.logger.error("Authentik sign-in failed: #{e.class} #{e.message}")
    redirect_to root_path, alert: 'Unable to sign you in. Please try again.'
  end

  def create_local
    unless local_auth_enabled?
      redirect_to login_path, alert: 'Local authentication is disabled.'
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
      flash.now[:alert] = 'Invalid email or password.'
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    reset_session
    redirect_to root_path, notice: 'Signed out successfully.'
  end

  def create_rfid
    # Store session timestamp to match with webhook data
    session[:waiting_for_keyfob] = Time.current.to_i
    redirect_to rfid_wait_path
  end

  def rfid_wait
    unless session[:waiting_for_keyfob].present?
      redirect_to login_path, alert: 'No keyfob session found. Please try again.'
      return
    end

    # Check if any webhook data is available (created after session started)
    session_start = Time.at(session[:waiting_for_keyfob])
    webhook_data = RfidWebhookService.find_recent(session_start)
    
    if webhook_data.present?
      # Store the RFID from webhook in session for verification
      session[:pending_rfid] = webhook_data[:rfid]
      redirect_to rfid_verify_path
      return
    end
  end

  def rfid_verify
    rfid = session[:pending_rfid]
    unless rfid.present?
      redirect_to rfid_wait_path, alert: 'Waiting for keyfob scan. Please try again.'
      return
    end

    # Verify webhook data is still available
    @webhook_data = RfidWebhookService.retrieve(rfid)
    unless @webhook_data.present?
      redirect_to rfid_wait_path, alert: 'Waiting for keyfob scan. Please try again.'
      return
    end

    @reader_name = @webhook_data[:reader_name]
  end

  def rfid_check_webhook
    unless session[:waiting_for_keyfob].present?
      render json: { status: 'no_session' }, status: :ok
      return
    end

    session_start = Time.at(session[:waiting_for_keyfob])
    webhook_data = RfidWebhookService.find_recent(session_start)
    
    if webhook_data.present?
      # Store the RFID from webhook in session
      session[:pending_rfid] = webhook_data[:rfid]
      render json: { status: 'ready' }, status: :ok
    else
      render json: { status: 'waiting' }, status: :ok
    end
  end

  def rfid_submit_pin
    rfid = session[:pending_rfid]
    pin = params[:pin] || params[:rfid]&.dig(:pin)

    if rfid.blank?
      redirect_to login_path, alert: 'No keyfob session found. Please try again.'
      return
    end

    if pin.blank?
      redirect_to rfid_verify_path, alert: 'Please enter the 4-digit code.'
      return
    end

    # Verify the pin
    if RfidWebhookService.verify_and_consume(rfid, pin)
      # Pin is correct, log in the user
      user = find_user_by_rfid(rfid)
      if user
        session.delete(:pending_rfid)
        session.delete(:waiting_for_keyfob)
        user.update!(last_login_at: Time.current)
        session[:user_id] = user.id
        redirect_to root_path, notice: "Signed in via keyfob as #{user.display_name}."
      else
        redirect_to login_path, alert: 'User not found. Please try again.'
      end
    else
      redirect_to rfid_verify_path, alert: 'Invalid code. Please try again.'
    end
  end

  def failure
    redirect_to root_path, alert: params[:message] || 'Authentication failed.'
  end

  private

  def upsert_user_from_auth(auth)
    payload = auth.respond_to?(:deep_symbolize_keys) ? auth.deep_symbolize_keys : {}
    info = payload.fetch(:info, {})
    extra = payload.fetch(:extra, {}).fetch(:raw_info, {})

    authentik_id = payload[:uid].to_s
    email = info[:email] || extra[:email]
    username = info[:nickname] || info[:preferred_username] || extra[:username]
    full_name = info[:name] || build_full_name(info, extra)

    # First, try to find by authentik_id
    user = User.find_by(authentik_id: authentik_id) if authentik_id.present?

    # If not found and we have an email, try to find by email
    if user.nil? && email.present?
      normalized_email = email.to_s.strip.downcase
      user = User.find_by('LOWER(email) = ?', normalized_email) if normalized_email.present?
    end

    # If still not found, initialize a new user
    user ||= User.new

    # Set authentik_id if it's not already set
    user.authentik_id = authentik_id if authentik_id.present? && user.authentik_id.blank?

    # Merge in email only if blank (don't overwrite existing email)
    user.email = email if user.email.blank? && email.present?

    # Merge in full_name only if blank (don't overwrite existing name)
    user.full_name = full_name if user.full_name.blank? && full_name.present?

    # Merge in username from Authentik
    user.username = username if username.present?

    # Always update these fields on login
    user.active = true
    user.last_synced_at = Time.current

    user.save!
    user
  end

  def sync_local_account(account)
    User.find_or_initialize_by(authentik_id: "local:#{account.id}").tap do |user|
      user.assign_attributes(
        email: account.email,
        full_name: account.full_name,
        active: account.active,
        last_synced_at: Time.current,
        is_admin: account.admin?
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

    LocalAccount.find_by('LOWER(email) = ?', normalized_email)
  end

  def build_full_name(info, extra)
    parts = [
      info[:first_name],
      info[:last_name],
      extra[:first_name],
      extra[:last_name]
    ].compact_blank

    parts.presence&.join(' ')
  end

  def find_user_by_rfid(value)
    normalized = value.to_s.strip.downcase
    return if normalized.blank?

    # Search in the rfids table
    rfid_record = Rfid.where('LOWER(rfid) = ?', normalized).joins(:user).where(users: { active: true }).first
    rfid_record&.user
  end
end
