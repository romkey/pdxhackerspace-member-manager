require 'test_helper'

class QueuedMailsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_local_auth_enabled = Rails.application.config.x.local_auth.enabled
    Rails.application.config.x.local_auth.enabled = true
    sign_in_as_local_admin
    @pending = queued_mails(:pending_mail)
    @approved = queued_mails(:approved_mail)
    @original_smtp = Rails.configuration.action_mailer.smtp_settings&.dup
    Rails.configuration.action_mailer.smtp_settings = { address: 'smtp.test.example.com', user_name: 'test',
                                                        password: 'test' }
  end

  teardown do
    Rails.configuration.action_mailer.smtp_settings = @original_smtp
    Rails.application.config.x.local_auth.enabled = @original_local_auth_enabled
  end

  # ─── Index ────────────────────────────────────────────────────────

  test 'shows index with pending filter by default' do
    get queued_mails_path
    assert_response :success
    assert_select 'h1', /Mail Queue/
  end

  test 'shows index with approved filter' do
    get queued_mails_path(filter: 'approved')
    assert_response :success
  end

  test 'shows index with rejected filter' do
    get queued_mails_path(filter: 'rejected')
    assert_response :success
  end

  test 'shows index with all filter' do
    get queued_mails_path(filter: 'all')
    assert_response :success
  end

  # ─── Show ─────────────────────────────────────────────────────────

  test 'shows queued mail' do
    get queued_mail_path(@pending)
    assert_response :success
    assert_match @pending.subject, response.body
    assert_match @pending.to, response.body
  end

  # ─── Edit ─────────────────────────────────────────────────────────

  test 'shows edit form for pending mail' do
    get edit_queued_mail_path(@pending)
    assert_response :success
    assert_select 'form'
  end

  test 'redirects edit for non-pending mail' do
    get edit_queued_mail_path(@approved)
    assert_redirected_to queued_mail_path(@approved)
  end

  # ─── Update ───────────────────────────────────────────────────────

  test 'updates pending mail' do
    patch queued_mail_path(@pending), params: {
      queued_mail: {
        subject: 'Updated Subject',
        body_html: '<p>Updated body</p>'
      }
    }
    assert_redirected_to queued_mail_path(@pending)
    @pending.reload
    assert_equal 'Updated Subject', @pending.subject
  end

  test 'rejects update for non-pending mail' do
    patch queued_mail_path(@approved), params: {
      queued_mail: { subject: 'Should not update' }
    }
    assert_redirected_to queued_mail_path(@approved)
    @approved.reload
    assert_not_equal 'Should not update', @approved.subject
  end

  # ─── Approve ──────────────────────────────────────────────────────

  test 'approves pending mail and sends it' do
    assert_enqueued_jobs 1, only: QueuedMailDeliveryJob do
      post approve_queued_mail_path(@pending)
    end
    assert_redirected_to queued_mails_path

    @pending.reload
    assert @pending.approved?
    # sent_at is set when the delivery job runs, not when enqueued
  end

  test 'cannot approve already reviewed mail' do
    post approve_queued_mail_path(@approved)
    assert_redirected_to queued_mail_path(@approved)
  end

  # ─── Reject ──────────────────────────────────────────────────────

  test 'rejects pending mail' do
    post reject_queued_mail_path(@pending)
    assert_redirected_to queued_mails_path

    @pending.reload
    assert @pending.rejected?
    assert_nil @pending.sent_at
  end

  test 'cannot reject already reviewed mail' do
    post reject_queued_mail_path(@approved)
    assert_redirected_to queued_mail_path(@approved)
  end

  # ─── Regenerate ──────────────────────────────────────────────────

  test 'regenerates pending mail from view template' do
    post regenerate_queued_mail_path(@pending)
    assert_redirected_to queued_mail_path(@pending)
  end

  test 'cannot regenerate non-pending mail' do
    post regenerate_queued_mail_path(@approved)
    assert_redirected_to queued_mail_path(@approved)
  end

  test 'rewrite_with_ai rewrites body in place for pending mail' do
    ai_ollama_profiles(:default).update!(base_url: 'http://ollama.test:11434', model: 'llama3.2')
    ai_ollama_profiles(:email_rewriting).update!(enabled: true, base_url: '', model: '', prompt: 'Rewrite this email.')

    response_json = {
      body_html: '<p>Rewritten HTML</p>',
      body_text: 'Rewritten text'
    }
    stub_result = Ollama::ChatCompletion::Result.new(true, JSON.generate(response_json), nil)

    original_call = Ollama::ChatCompletion.method(:call)
    Ollama::ChatCompletion.define_singleton_method(:call) { |**_kwargs| stub_result }
    begin
      post rewrite_with_ai_queued_mail_path(@pending), params: {
        rewrite: {
          subject: @pending.subject,
          body_html: @pending.body_html,
          body_text: @pending.body_text
        }
      }, as: :json
    ensure
      Ollama::ChatCompletion.define_singleton_method(:call, original_call)
    end

    assert_response :success
    parsed = response.parsed_body
    assert_equal '<p>Rewritten HTML</p>', parsed['body_html']
    assert_equal 'Rewritten text', parsed['body_text']
  end

  test 'rewrite_with_ai rejects non-pending mail' do
    post rewrite_with_ai_queued_mail_path(@approved), params: {
      rewrite: {
        subject: @approved.subject,
        body_html: @approved.body_html,
        body_text: @approved.body_text
      }
    }, as: :json

    assert_response :unprocessable_content
    parsed = response.parsed_body
    assert_match(/Only pending messages/, parsed['error'])
  end

  # ─── Admin access required ────────────────────────────────────────

  test 'non-admin cannot access queue' do
    delete logout_path
    get queued_mails_path
    assert_redirected_to login_path
  end

  private

  def sign_in_as_local_admin
    account = local_accounts(:active_admin)
    post local_login_path, params: {
      session: {
        email: account.email,
        password: 'localpassword123'
      }
    }
  end
end
