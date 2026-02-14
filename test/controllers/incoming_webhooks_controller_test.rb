require 'test_helper'

class IncomingWebhooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @webhook = incoming_webhooks(:rfid_webhook)
    @disabled_webhook = incoming_webhooks(:disabled_webhook)
    @original_local_auth_enabled = Rails.application.config.x.local_auth.enabled
    Rails.application.config.x.local_auth.enabled = true
    sign_in_as_admin
  end

  teardown do
    Rails.application.config.x.local_auth.enabled = @original_local_auth_enabled
  end

  # ==========================================
  # INDEX
  # ==========================================

  test 'admin can view incoming webhooks index' do
    get incoming_webhooks_url
    assert_response :success
    assert_match @webhook.name, response.body
  end

  test 'unauthenticated user is redirected from index' do
    reset!
    get incoming_webhooks_url
    assert_response :redirect
  end

  # ==========================================
  # EDIT
  # ==========================================

  test 'admin can view edit page' do
    get edit_incoming_webhook_url(@webhook)
    assert_response :success
    assert_match @webhook.name, response.body
    assert_match @webhook.slug, response.body
  end

  test 'edit page shows slug in editable field' do
    get edit_incoming_webhook_url(@webhook)
    assert_response :success
    assert_select "input[name='incoming_webhook[slug]'][value='#{@webhook.slug}']"
  end

  test 'edit page shows randomize button' do
    get edit_incoming_webhook_url(@webhook)
    assert_response :success
    assert_select '#randomize-slug-btn'
  end

  # ==========================================
  # UPDATE - slug changes
  # ==========================================

  test 'admin can update slug' do
    new_slug = 'my-custom-rfid-slug'
    patch incoming_webhook_url(@webhook), params: {
      incoming_webhook: { slug: new_slug }
    }
    assert_redirected_to incoming_webhooks_path
    @webhook.reload
    assert_equal new_slug, @webhook.slug
  end

  test 'slug change persists and is used for webhook URL' do
    new_slug = 'new-rfid-endpoint'
    patch incoming_webhook_url(@webhook), params: {
      incoming_webhook: { slug: new_slug }
    }
    @webhook.reload
    assert_equal new_slug, @webhook.slug
    assert_match "/webhooks/#{new_slug}", @webhook.webhook_path
  end

  test 'rejects blank slug' do
    patch incoming_webhook_url(@webhook), params: {
      incoming_webhook: { slug: '' }
    }
    assert_response :unprocessable_content
    @webhook.reload
    assert_equal 'rfid', @webhook.slug
  end

  test 'rejects slug with invalid characters' do
    patch incoming_webhook_url(@webhook), params: {
      incoming_webhook: { slug: 'has spaces!' }
    }
    assert_response :unprocessable_content
    @webhook.reload
    assert_equal 'rfid', @webhook.slug
  end

  test 'rejects duplicate slug' do
    patch incoming_webhook_url(@webhook), params: {
      incoming_webhook: { slug: @disabled_webhook.slug }
    }
    assert_response :unprocessable_content
    @webhook.reload
    assert_equal 'rfid', @webhook.slug
  end

  test 'allows keeping the same slug' do
    patch incoming_webhook_url(@webhook), params: {
      incoming_webhook: { slug: @webhook.slug }
    }
    assert_redirected_to incoming_webhooks_path
    @webhook.reload
    assert_equal 'rfid', @webhook.slug
  end

  # ==========================================
  # UPDATE - other fields
  # ==========================================

  test 'admin can update description' do
    patch incoming_webhook_url(@webhook), params: {
      incoming_webhook: { description: 'Updated description' }
    }
    assert_redirected_to incoming_webhooks_path
    @webhook.reload
    assert_equal 'Updated description', @webhook.description
  end

  test 'admin can toggle enabled' do
    assert_predicate @webhook, :enabled?
    patch incoming_webhook_url(@webhook), params: {
      incoming_webhook: { enabled: false }
    }
    assert_redirected_to incoming_webhooks_path
    @webhook.reload
    assert_not_predicate @webhook, :enabled?
  end

  test 'admin can update slug and description together' do
    patch incoming_webhook_url(@webhook), params: {
      incoming_webhook: { slug: 'new-slug', description: 'New desc' }
    }
    assert_redirected_to incoming_webhooks_path
    @webhook.reload
    assert_equal 'new-slug', @webhook.slug
    assert_equal 'New desc', @webhook.description
  end

  # ==========================================
  # RANDOM SLUG
  # ==========================================

  test 'random_slug returns JSON with a slug' do
    get random_slug_incoming_webhooks_url, headers: { 'Accept' => 'application/json' }
    assert_response :success
    json = response.parsed_body
    assert json['slug'].present?
    assert_match(/\A[a-zA-Z0-9_-]+\z/, json['slug'])
  end

  test 'random_slug returns unique slugs' do
    get random_slug_incoming_webhooks_url, headers: { 'Accept' => 'application/json' }
    slug1 = response.parsed_body['slug']
    get random_slug_incoming_webhooks_url, headers: { 'Accept' => 'application/json' }
    slug2 = response.parsed_body['slug']
    assert_not_equal slug1, slug2
  end

  # ==========================================
  # SEED
  # ==========================================

  test 'seed creates default webhooks' do
    IncomingWebhook.delete_all
    post seed_incoming_webhooks_url
    assert_redirected_to incoming_webhooks_path
    assert_operator IncomingWebhook.count, :>=, 1
  end

  # ==========================================
  # NON-ADMIN ACCESS
  # ==========================================

  test 'non-admin member cannot access incoming webhooks' do
    reset!
    Rails.application.config.x.local_auth.enabled = true
    sign_in_as_member
    get incoming_webhooks_url
    assert_response :redirect
  end

  private

  def sign_in_as_admin
    account = local_accounts(:active_admin)
    post local_login_path, params: {
      session: { email: account.email, password: 'localpassword123' }
    }
  end

  def sign_in_as_member
    account = local_accounts(:regular_member)
    post local_login_path, params: {
      session: { email: account.email, password: 'memberpassword123' }
    }
  end
end
