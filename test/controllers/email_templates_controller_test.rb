require 'test_helper'

class EmailTemplatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_local_auth_enabled = Rails.application.config.x.local_auth.enabled
    Rails.application.config.x.local_auth.enabled = true
    sign_in_as_admin
    @template = EmailTemplate.create!(
      key: 'rewrite_test_template',
      name: 'Rewrite Test Template',
      subject: 'Initial Subject',
      body_html: '<p>Initial HTML</p>',
      body_text: 'Initial text',
      enabled: true
    )
  end

  teardown do
    Rails.application.config.x.local_auth.enabled = @original_local_auth_enabled
  end

  test 'rewrite_with_ai rewrites subject and body' do
    ai_ollama_profiles(:default).update!(base_url: 'http://ollama.test:11434', model: 'llama3.2')
    ai_ollama_profiles(:email_rewriting).update!(enabled: true, base_url: '', model: '', prompt: 'Rewrite template.')

    response_json = {
      subject: 'Improved Subject',
      body_html: '<p>Improved HTML</p>',
      body_text: 'Improved text'
    }
    stub_result = Ollama::ChatCompletion::Result.new(true, JSON.generate(response_json), nil)

    original_call = Ollama::ChatCompletion.method(:call)
    Ollama::ChatCompletion.define_singleton_method(:call) { |**_kwargs| stub_result }
    begin
      post rewrite_with_ai_email_template_path(@template), params: {
        rewrite: {
          subject: @template.subject,
          body_html: @template.body_html,
          body_text: @template.body_text
        }
      }, as: :json
    ensure
      Ollama::ChatCompletion.define_singleton_method(:call, original_call)
    end

    assert_response :success
    parsed = response.parsed_body
    assert_equal 'Improved Subject', parsed['subject']
    assert_equal '<p>Improved HTML</p>', parsed['body_html']
    assert_equal 'Improved text', parsed['body_text']
  end

  test 'edit shows text sync checkbox checked by default' do
    get edit_email_template_path(@template)

    assert_response :success
    assert_select 'input#email_template_sync_body_text[name=?][checked]', 'sync_body_text'
    assert_select 'label[for=?]', 'email_template_sync_body_text', text: 'Keep in sync with HTML'
  end

  test 'show wraps html body in high contrast preview container' do
    get email_template_path(@template)

    assert_response :success
    assert_select '.email-template-html-body'
  end

  test 'update syncs plain text from html when checkbox is checked' do
    patch email_template_path(@template), params: {
      sync_body_text: '1',
      email_template: {
        name: @template.name,
        description: @template.description,
        subject: 'Updated Subject',
        body_html: '<h1>Welcome</h1><p>Hello <strong>{{member_name}}</strong><br>Line two</p>',
        body_text: 'Stale plain text',
        enabled: '1'
      }
    }

    assert_redirected_to email_templates_path
    @template.reload
    assert_equal '<h1>Welcome</h1><p>Hello <strong>{{member_name}}</strong><br>Line two</p>', @template.body_html
    assert_equal "Welcome\nHello {{member_name}}\nLine two", @template.body_text
  end

  test 'update sync lists link urls under their containing paragraph' do
    html = <<~HTML.squish
      <p>Visit <a href="https://example.com/start">the getting started guide</a>
      and <a href="{{application_url}}">your application</a>.</p>
      <p>Thanks for reading.</p>
    HTML

    patch email_template_path(@template), params: {
      sync_body_text: '1',
      email_template: {
        name: @template.name,
        description: @template.description,
        subject: 'Updated Subject',
        body_html: html,
        body_text: 'Stale plain text',
        enabled: '1'
      }
    }

    assert_redirected_to email_templates_path
    @template.reload
    assert_equal <<~TEXT.strip, @template.body_text
      Visit the getting started guide and your application.

      https://example.com/start
      {{application_url}}

      Thanks for reading.
    TEXT
  end

  test 'update leaves plain text unchanged when checkbox is unchecked' do
    patch email_template_path(@template), params: {
      email_template: {
        name: @template.name,
        description: @template.description,
        subject: 'Updated Subject',
        body_html: '<p>Replacement HTML</p>',
        body_text: 'Custom plain text',
        enabled: '1'
      }
    }

    assert_redirected_to email_templates_path
    @template.reload
    assert_equal '<p>Replacement HTML</p>', @template.body_html
    assert_equal 'Custom plain text', @template.body_text
  end

  private

  def sign_in_as_admin
    account = local_accounts(:active_admin)
    post local_login_path, params: {
      session: {
        email: account.email,
        password: 'localpassword123'
      }
    }
  end
end
