class QueuedMail < ApplicationRecord
  STATUSES = %w[pending approved rejected].freeze

  belongs_to :email_template, optional: true
  belongs_to :recipient, class_name: 'User', optional: true
  belongs_to :reviewed_by, class_name: 'User', optional: true
  has_many :mail_log_entries, dependent: :destroy

  validates :to, :subject, :body_html, :reason, :mailer_action, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: 'pending') }
  scope :approved, -> { where(status: 'approved') }
  scope :rejected, -> { where(status: 'rejected') }
  scope :unsent, -> { approved.where(sent_at: nil) }
  scope :failed, -> { approved.where(sent_at: nil).where.not(last_error: nil) }
  scope :newest_first, -> { order(created_at: :desc) }

  def pending?  = status == 'pending'
  def approved? = status == 'approved'
  def rejected? = status == 'rejected'

  def sent?
    approved? && sent_at.present?
  end

  def delivery_pending?
    approved? && sent_at.nil? && last_error.nil?
  end

  def delivery_failed?
    approved? && sent_at.nil? && last_error.present?
  end

  def self.enqueue(action, user, to: nil, reason: nil, **extra_args)
    dest = to || user.email
    return nil if dest.blank?

    template = EmailTemplate.find_enabled(action.to_s)
    variables = MemberMailer.build_template_variables(user, extra_args)

    record = if template
               rendered = template.render(variables)
               create!(
                 to: dest,
                 subject: rendered[:subject],
                 body_html: rendered[:body_html],
                 body_text: rendered[:body_text] || '',
                 reason: reason || action.to_s.humanize,
                 email_template: template,
                 recipient: user,
                 mailer_action: action.to_s,
                 mailer_args: extra_args
               )
             else
               message = MemberMailer.public_send(action, *build_mailer_args(action, user, to, extra_args))
               msg = message.message

               html_body = msg.multipart? ? msg.html_part&.body&.decoded : msg.body.decoded
               text_body = msg.multipart? ? msg.text_part&.body&.decoded : ''

               create!(
                 to: dest,
                 subject: msg.subject,
                 body_html: html_body || '',
                 body_text: text_body || '',
                 reason: reason || action.to_s.humanize,
                 recipient: user,
                 mailer_action: action.to_s,
                 mailer_args: extra_args
               )
             end

    MailLogEntry.log!(record, 'created', details: "Queued #{action.to_s.humanize} to #{dest}")
    record
  end

  def approve!(reviewer)
    update!(status: 'approved', reviewed_by: reviewer, reviewed_at: Time.current)
    MailLogEntry.log!(self, 'approved', actor: reviewer, details: "Approved for delivery to #{to}")
    QueuedMailDeliveryJob.perform_later(id)
  end

  def reject!(reviewer)
    update!(status: 'rejected', reviewed_by: reviewer, reviewed_at: Time.current)
    MailLogEntry.log!(self, 'rejected', actor: reviewer, details: 'Rejected, not sent')
  end

  def log_edit!(actor)
    MailLogEntry.log!(self, 'edited', actor: actor, details: 'Message content edited')
  end

  def regenerate!(actor: nil)
    if email_template && recipient
      args = (mailer_args || {}).symbolize_keys
      variables = MemberMailer.build_template_variables(recipient, args)
      rendered = email_template.render(variables)
      update!(
        subject: rendered[:subject],
        body_html: rendered[:body_html],
        body_text: rendered[:body_text] || ''
      )
    elsif recipient
      message = MemberMailer.public_send(
        mailer_action,
        *self.class.build_mailer_args(mailer_action, recipient, to, (mailer_args || {}).symbolize_keys)
      )
      msg = message.message
      html_body = msg.multipart? ? msg.html_part&.body&.decoded : msg.body.decoded
      text_body = msg.multipart? ? msg.text_part&.body&.decoded : ''
      update!(subject: msg.subject, body_html: html_body || '', body_text: text_body || '')
    end
    MailLogEntry.log!(self, 'regenerated', actor: actor, details: 'Regenerated from template')
  end

  def can_regenerate?
    recipient.present? && (email_template.present? || mailer_action.present?)
  end

  def deliver_now!
    increment!(:send_attempts)
    QueuedMailMailer.deliver_queued(self).deliver_now
    update!(sent_at: Time.current, last_error: nil, last_error_at: nil)
    MailLogEntry.log!(self, 'sent', details: "Delivered to #{to}")
  rescue StandardError => e
    record_delivery_failure!(e)
    raise
  end

  def retry_delivery!
    update!(last_error: nil, last_error_at: nil)
    QueuedMailDeliveryJob.perform_later(id)
  end

  def record_delivery_failure!(error)
    error_message = "#{error.class}: #{error.message}"
    update!(last_error: error_message, last_error_at: Time.current)
    MailLogEntry.log_once!(self, 'send_failed', details: error_message)
  end

  def self.build_mailer_args(action, user, to_addr, extra_args)
    case action.to_s
    when 'admin_new_application'
      [user, to_addr || extra_args[:admin_email]]
    when 'payment_past_due'
      [user, { days_overdue: extra_args[:days_overdue] }.compact]
    when 'membership_cancelled', 'membership_banned'
      [user, { reason: extra_args[:reason] }.compact]
    when 'training_completed', 'trainer_capability_granted'
      [user, { training_topic: extra_args[:training_topic] }.compact]
    else
      [user]
    end
  end
end
