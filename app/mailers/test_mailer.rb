# Mailer for sending test emails from email templates
class TestMailer < ApplicationMailer
  def send_template(to:, subject:, body_html:, body_text:)
    @body_html = body_html
    @body_text = body_text

    mail(
      to: to,
      subject: subject
    ) do |format|
      format.html { render html: @body_html.html_safe, layout: 'mailer' }
      format.text { render plain: @body_text }
    end
  end
end
