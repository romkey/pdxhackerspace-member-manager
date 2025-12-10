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
    # COMPREHENSIVE DUMP - Log EVERYTHING from Authentik OAuth response
    Rails.logger.info("=" * 100)
    Rails.logger.info("AUTHENTIK OAUTH LOGIN - COMPLETE DATA DUMP")
    Rails.logger.info("=" * 100)
    
    # Log raw object metadata
    Rails.logger.info("Raw auth object class: #{auth.class}")
    Rails.logger.info("Raw auth object inspect: #{auth.inspect}")
    
    # Try multiple ways to convert to hash
    auth_hash = nil
    if auth.respond_to?(:to_h)
      auth_hash = auth.to_h
      Rails.logger.info("Converted via to_h")
    elsif auth.respond_to?(:deep_symbolize_keys)
      auth_hash = auth.deep_symbolize_keys
      Rails.logger.info("Converted via deep_symbolize_keys")
    elsif auth.is_a?(Hash)
      auth_hash = auth
      Rails.logger.info("Already a Hash")
    else
      # Try to convert via JSON
      begin
        auth_hash = JSON.parse(auth.to_json) if auth.respond_to?(:to_json)
        Rails.logger.info("Converted via JSON round-trip")
      rescue => e
        Rails.logger.info("Could not convert to hash: #{e.message}")
        auth_hash = { raw: auth.inspect }
      end
    end
    
    # Dump the ENTIRE auth hash as raw JSON - no filtering
    Rails.logger.info("-" * 100)
    Rails.logger.info("COMPLETE AUTH HASH (RAW JSON):")
    Rails.logger.info("-" * 100)
    begin
      Rails.logger.info(JSON.pretty_generate(auth_hash.as_json))
    rescue => e
      Rails.logger.info("JSON serialization failed: #{e.message}")
      Rails.logger.info("Falling back to inspect:")
      Rails.logger.info(auth_hash.inspect)
    end
    
    # Also dump as YAML for alternative view
    begin
      require 'yaml'
      Rails.logger.info("-" * 100)
      Rails.logger.info("COMPLETE AUTH HASH (YAML):")
      Rails.logger.info("-" * 100)
      Rails.logger.info(auth_hash.to_yaml)
    rescue => e
      Rails.logger.info("YAML serialization failed: #{e.message}")
    end
    
    # Recursively dump all keys and values
    Rails.logger.info("-" * 100)
    Rails.logger.info("RECURSIVE KEY/VALUE DUMP:")
    Rails.logger.info("-" * 100)
    dump_hash_recursive(auth_hash, prefix: "  ")
    
    # Extract sections for detailed inspection
    payload = auth.respond_to?(:deep_symbolize_keys) ? auth.deep_symbolize_keys : (auth_hash || {})
    info = payload.fetch(:info, {})
    extra_hash = payload.fetch(:extra, {})
    extra = extra_hash.fetch(:raw_info, {})
    
    # Dump each section separately with full detail
    Rails.logger.info("-" * 100)
    Rails.logger.info("PAYLOAD SECTION (complete):")
    Rails.logger.info("-" * 100)
    dump_hash_recursive(payload, prefix: "  ")
    Rails.logger.info("Payload JSON:")
    Rails.logger.info(JSON.pretty_generate(payload.as_json))
    
    Rails.logger.info("-" * 100)
    Rails.logger.info("INFO SECTION (complete):")
    Rails.logger.info("-" * 100)
    dump_hash_recursive(info, prefix: "  ")
    Rails.logger.info("Info JSON:")
    Rails.logger.info(JSON.pretty_generate(info.as_json))
    
    Rails.logger.info("-" * 100)
    Rails.logger.info("EXTRA SECTION (complete):")
    Rails.logger.info("-" * 100)
    dump_hash_recursive(extra_hash, prefix: "  ")
    Rails.logger.info("Extra JSON:")
    Rails.logger.info(JSON.pretty_generate(extra_hash.as_json))
    
    Rails.logger.info("-" * 100)
    Rails.logger.info("RAW_INFO SECTION (complete):")
    Rails.logger.info("-" * 100)
    dump_hash_recursive(extra, prefix: "  ")
    Rails.logger.info("Raw info JSON:")
    Rails.logger.info(JSON.pretty_generate(extra.as_json))
    
    # Log all keys at every level
    Rails.logger.info("-" * 100)
    Rails.logger.info("ALL KEYS AT EVERY LEVEL:")
    Rails.logger.info("-" * 100)
    Rails.logger.info("  Top-level keys: #{auth_hash.keys.inspect if auth_hash.respond_to?(:keys)}")
    Rails.logger.info("  payload keys: #{payload.keys.inspect}")
    Rails.logger.info("  info keys: #{info.keys.inspect}")
    Rails.logger.info("  extra keys: #{extra_hash.keys.inspect}")
    Rails.logger.info("  raw_info keys: #{extra.respond_to?(:keys) ? extra.keys.inspect : extra.inspect}")
    
    # Log extracted values
    authentik_id = payload[:uid].to_s
    email = info[:email] || extra[:email]
    username = info[:nickname] || info[:preferred_username] || extra[:username]
    full_name = info[:name] || build_full_name(info, extra)
    
    Rails.logger.info("-" * 100)
    Rails.logger.info("EXTRACTED VALUES:")
    Rails.logger.info("-" * 100)
    Rails.logger.info("  authentik_id: #{authentik_id.inspect}")
    Rails.logger.info("  email: #{email.inspect}")
    Rails.logger.info("  username: #{username.inspect}")
    Rails.logger.info("  full_name: #{full_name.inspect}")
    
    # Search for any admin-related keys
    Rails.logger.info("-" * 100)
    Rails.logger.info("SEARCHING FOR ADMIN-RELATED KEYS:")
    Rails.logger.info("-" * 100)
    search_for_keys(auth_hash, /admin/i, prefix: "  ")
    
    Rails.logger.info("=" * 100)

    # Extract admin status from Authentik
    is_admin = extract_admin_status(info, extra)

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

    # Update admin status from Authentik (only if we got a value from Authentik)
    user.is_admin = is_admin unless is_admin.nil?

    # Always update these fields on login
    user.active = true
    user.last_synced_at = Time.current

    user.save!
    user
  end

  def dump_hash_recursive(hash, prefix: "", depth: 0, max_depth: 10)
    return if depth > max_depth
    
    return unless hash.is_a?(Hash) || hash.is_a?(Array)
    
    if hash.is_a?(Array)
      hash.each_with_index do |item, index|
        Rails.logger.info("#{prefix}[#{index}]: #{item.inspect}")
        if item.is_a?(Hash) || item.is_a?(Array)
          dump_hash_recursive(item, prefix: "#{prefix}  ", depth: depth + 1, max_depth: max_depth)
        end
      end
    else
      hash.each do |key, value|
        if value.is_a?(Hash) || value.is_a?(Array)
          Rails.logger.info("#{prefix}#{key.inspect}:")
          dump_hash_recursive(value, prefix: "#{prefix}  ", depth: depth + 1, max_depth: max_depth)
        else
          Rails.logger.info("#{prefix}#{key.inspect}: #{value.inspect}")
        end
      end
    end
  end

  def search_for_keys(hash, pattern, prefix: "", path: "")
    return unless hash.is_a?(Hash) || hash.is_a?(Array)
    
    if hash.is_a?(Array)
      hash.each_with_index do |item, index|
        new_path = "#{path}[#{index}]"
        if item.is_a?(Hash) || item.is_a?(Array)
          search_for_keys(item, pattern, prefix: prefix, path: new_path)
        elsif item.to_s.match?(pattern)
          Rails.logger.info("#{prefix}#{new_path}: #{item.inspect}")
        end
      end
    else
      hash.each do |key, value|
        new_path = path.empty? ? key.to_s : "#{path}.#{key}"
        
        if key.to_s.match?(pattern)
          Rails.logger.info("#{prefix}#{new_path}: #{value.inspect}")
        end
        
        if value.is_a?(Hash) || value.is_a?(Array)
          search_for_keys(value, pattern, prefix: prefix, path: new_path)
        elsif value.to_s.match?(pattern)
          Rails.logger.info("#{prefix}#{new_path}: #{value.inspect}")
        end
      end
    end
  end

  def extract_admin_status(info, extra)
    # Check for explicit admin claim (boolean or string)
    # This should be set by an Authentik property mapping that checks group membership
    admin_claim = info[:is_admin] || info[:admin] || extra[:is_admin] || extra[:admin]
    
    if admin_claim.present?
      # Handle boolean, string "true"/"false", or "1"/"0"
      return true if admin_claim == true || admin_claim.to_s.downcase.in?(%w[true 1 yes])
      return false if admin_claim == false || admin_claim.to_s.downcase.in?(%w[false 0 no])
    end

    nil # Return nil if no admin status found (don't update the field)
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
