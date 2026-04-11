class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch('EMAIL_FROM_ADDRESS', 'noreply@example.com') }
  layout 'mailer'

  after_action :set_member_manager_mail_trace_headers

  private

  def set_member_manager_mail_trace_headers
    headers['X-MemberManager-Mailer'] = self.class.name
    headers['X-MemberManager-Action'] = action_name.to_s
  end

  # Helper to get the organization name for emails
  def organization_name
    ENV.fetch('ORGANIZATION_NAME', 'Member Manager')
  end

  # Helper to get the support email
  def support_email
    ENV.fetch('EMAIL_SUPPORT_ADDRESS', ENV.fetch('EMAIL_FROM_ADDRESS', 'support@example.com'))
  end
end
