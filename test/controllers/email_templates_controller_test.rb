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
