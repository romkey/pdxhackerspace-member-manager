class QueuedMailMailer < ApplicationMailer
  skip_after_action :set_member_manager_mail_trace_headers
  after_action :mark_skip_duplicate_mail_log

  def deliver_queued(queued_mail)
    @body_html = queued_mail.body_html
    @body_text = queued_mail.body_text

    mail(to: queued_mail.to, subject: queued_mail.subject) do |format|
      format.html { render html: @body_html.html_safe, layout: 'mailer' }
      format.text { render plain: @body_text } if @body_text.present?
    end
  end

  private

  def mark_skip_duplicate_mail_log
    headers['X-MemberManager-Skip-MailLog'] = '1'
  end
end
