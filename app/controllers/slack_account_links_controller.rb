# frozen_string_literal: true

class SlackAccountLinksController < ApplicationController
  before_action :require_authenticated_user!
  before_action :ensure_slack_oidc_configured

  # Begins Sign in with Slack (OIDC) to obtain the member's Slack user id — not MM login.
  def new
    state = SecureRandom.hex(24)
    nonce = SecureRandom.hex(24)
    session[:slack_oidc_state] = state
    session[:slack_oidc_nonce] = nonce

    redirect_to Slack::OpenidConnect.authorization_uri(
      state: state,
      nonce: nonce,
      redirect_uri: slack_link_callback_url,
      team_id: SlackOidcConfig.settings.team_id
    ), allow_other_host: true
  end

  def callback
    return redirect_oauth_error if params[:error].present?
    return redirect_state_mismatch unless slack_state_valid?

    session.delete(:slack_oidc_state)
    nonce = session.delete(:slack_oidc_nonce)
    code = params[:code].presence
    return redirect_missing_code if code.blank?

    token_response = Slack::OpenidConnect.exchange_code(code: code, redirect_uri: slack_link_callback_url)
    return redirect_token_error(token_response) unless token_response['ok']

    payload = Slack::OpenidConnect.decode_id_token!(token_response['id_token'])
    return redirect_nonce_mismatch if nonce_mismatch?(nonce, payload)

    finish_link(payload)
  end

  private

  def redirect_oauth_error
    detail = params[:error_description].presence || params[:error]
    redirect_to after_link_path, alert: "Slack authorization failed: #{detail}"
  end

  def slack_state_valid?
    session[:slack_oidc_state].present? && params[:state].present? &&
      session[:slack_oidc_state] == params[:state]
  end

  def redirect_state_mismatch
    redirect_to after_link_path, alert: 'Invalid or expired Slack link attempt. Please try again.'
  end

  def redirect_missing_code
    redirect_to after_link_path, alert: 'Missing authorization code from Slack.'
  end

  def redirect_token_error(token_response)
    err = token_response['error'].presence || 'unknown error'
    redirect_to after_link_path, alert: "Slack token exchange failed: #{err}"
  end

  def nonce_mismatch?(nonce, payload)
    nonce.present? && payload['nonce'].present? && payload['nonce'] != nonce
  end

  def redirect_nonce_mismatch
    redirect_to after_link_path, alert: 'Slack login verification failed (nonce). Please try again.'
  end

  def finish_link(payload)
    result = Slack::AccountLinker.call(user: current_user, id_token_payload: payload)
    if result.success?
      redirect_to after_link_path, notice: result.message
    else
      redirect_to after_link_path, alert: result.message
    end
  end

  def ensure_slack_oidc_configured
    return if SlackOidcConfig.configured?

    redirect_to after_link_path, alert: 'Associating a Slack account is not configured yet.'
  end

  def after_link_path
    if current_user_admin?
      root_path(tab: :member_dashboard)
    else
      user_path(current_user, tab: :dashboard)
    end
  end
end
