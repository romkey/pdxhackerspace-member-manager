# Mailer for member-related notifications
# Uses database templates when available, falls back to view templates
# rubocop:disable Metrics/ClassLength -- many small mailer actions; extraction would fragment templates
class MemberMailer < ApplicationMailer
  include Rails.application.routes.url_helpers

  # Sent when a new member application is submitted
  def application_received(user)
    @user = user
    @organization = organization_name

    if send_from_template('application_received', user)
      # Email sent from database template
    else
      mail(
        to: @user.email,
        subject: "#{@organization}: Application Received"
      )
    end
  end

  # Sent when a member application is approved
  def application_approved(user)
    @user = user
    @organization = organization_name

    if send_from_template('application_approved', user)
      # Email sent from database template
    else
      mail(
        to: @user.email,
        subject: "#{@organization}: Welcome! Your Application Has Been Approved"
      )
    end
  end

  # Sent when a membership application is rejected (+recipient+ may be a User or ApplicantMailRecipient)
  def application_rejected(recipient, opts = {})
    reason = opts.is_a?(Hash) ? opts[:reason] : opts
    @user = recipient
    @organization = organization_name
    @reason = reason

    extra_vars = {}
    extra_vars[:reason] = reason if reason.present?

    if send_from_template('application_rejected', recipient, extra_vars)
      # Email sent from database template
    else
      mail(
        to: recipient.email,
        subject: "#{@organization}: Update on Your Membership Application"
      )
    end
  end

  # Sent when a member's payment is past due
  def payment_past_due(user, days_overdue: nil)
    @user = user
    @organization = organization_name
    @days_overdue = days_overdue

    extra_vars = { days_overdue: days_overdue ? " by #{days_overdue} days" : '' }

    if send_from_template('payment_past_due', user, extra_vars)
      # Email sent from database template
    else
      mail(
        to: @user.email,
        subject: "#{@organization}: Payment Reminder"
      )
    end
  end

  # Sent when a membership is cancelled (voluntary or involuntary)
  def membership_cancelled(user, opts = {})
    reason = opts.is_a?(Hash) ? opts[:reason] : opts
    @user = user
    @organization = organization_name
    @reason = reason

    extra_vars = { reason: reason.present? ? "<p><strong>Reason:</strong> #{reason}</p>" : '' }

    if send_from_template('membership_cancelled', user, extra_vars)
      # Email sent from database template
    else
      mail(
        to: @user.email,
        subject: "#{@organization}: Membership Cancelled"
      )
    end
  end

  # Sent when a member is banned
  def membership_banned(user, opts = {})
    reason = opts.is_a?(Hash) ? opts[:reason] : opts
    @user = user
    @organization = organization_name
    @reason = reason

    extra_vars = { reason: reason.present? ? "<p><strong>Reason:</strong> #{reason}</p>" : '' }

    if send_from_template('membership_banned', user, extra_vars)
      # Email sent from database template
    else
      mail(
        to: @user.email,
        subject: "#{@organization}: Account Suspended"
      )
    end
  end

  def membership_lapsed(user)
    @user = user
    @organization = organization_name

    if send_from_template('membership_lapsed', user)
      # Email sent from database template
    else
      mail(
        to: @user.email,
        subject: "#{@organization}: Your Membership Dues Have Lapsed"
      )
    end
  end

  def membership_sponsored(user)
    @user = user
    @organization = organization_name

    if send_from_template('membership_sponsored', user)
      # Email sent from database template
    else
      mail(
        to: @user.email,
        subject: "#{@organization}: Your Membership Has Been Sponsored!"
      )
    end
  end

  def training_completed(user, training_topic:)
    @user = user
    @organization = organization_name
    @training_topic = training_topic

    extra_vars = { training_topic: training_topic }

    if send_from_template('training_completed', user, extra_vars)
      # Email sent from database template
    else
      mail(
        to: @user.email,
        subject: "#{@organization}: You're Now Trained in #{training_topic}!"
      )
    end
  end

  def training_requested(user, opts = {})
    assign_training_requested_instance_vars(user, opts)
    extra_vars = training_requested_template_vars
    to_address = training_requested_to_address(user, opts)

    if send_from_template('training_requested', user, extra_vars, to: to_address)
      # Email sent from database template
    else
      mail(
        to: to_address,
        subject: "#{@organization}: Training request for #{@training_topic}"
      )
    end
  end

  def trainer_capability_granted(user, training_topic:)
    @user = user
    @organization = organization_name
    @training_topic = training_topic

    extra_vars = { training_topic: training_topic }

    if send_from_template('trainer_capability_granted', user, extra_vars)
      # Email sent from database template
    else
      mail(
        to: @user.email,
        subject: "#{@organization}: You Can Now Train Others in #{training_topic}!"
      )
    end
  end

  def parking_permit_issued(user, opts = {})
    send_parking_notice_mail('parking_permit_issued', user, opts)
  end

  def parking_ticket_issued(user, opts = {})
    send_parking_notice_mail('parking_ticket_issued', user, opts)
  end

  def parking_permit_expired(user, opts = {})
    send_parking_notice_mail('parking_permit_expired', user, opts)
  end

  def parking_ticket_expired(user, opts = {})
    send_parking_notice_mail('parking_ticket_expired', user, opts)
  end

  def application_email_verification(email, opts = {})
    @email = email
    @organization = organization_name
    @verification_url = opts[:verification_url] || opts['verification_url']
    @expires_in = opts[:expires_in] || opts['expires_in'] || '24 hours'

    mail(
      to: email,
      subject: "#{@organization}: Verify Your Email to Begin Your Membership Application"
    )
  end

  def login_link_sent(user, opts = {})
    @user = user
    @organization = organization_name
    @login_url = opts[:login_url] || opts['login_url']

    if send_from_template('login_link_sent', user, { login_url: @login_url })
      # Email sent from database template
    else
      mail(
        to: @user.email,
        subject: "#{@organization}: Your Login Link"
      )
    end
  end

  def login_link_expired(user, _opts = {})
    @user = user
    @organization = organization_name

    if send_from_template('login_link_expired', user)
      # Email sent from database template
    else
      mail(
        to: @user.email,
        subject: "#{@organization}: Your Login Link Has Expired"
      )
    end
  end

  # Notify admins of a new application (+opts+ may include +:application_url+ for that application’s admin page).
  def admin_new_application(applicant, admin_email, opts = {})
    opts = opts.symbolize_keys
    @user = applicant
    @organization = organization_name
    @admin_email = admin_email
    explicit_url = opts[:application_url].presence
    @application_url = explicit_url || membership_applications_fallback_url
    extra_vars = { application_url: @application_url }

    if send_from_template('admin_new_application', applicant, extra_vars, to: admin_email)
      # Email sent from database template
    else
      mail(
        to: admin_email,
        subject: "#{@organization}: New Member Application - #{@user.display_name}"
      )
    end
  end

  # Notify ED / Assistant ED trained staff (+deliver_later+, not QueuedMail).
  # +applicant+ comes from +QueuedMail.applicant_recipient_for(application)+.
  def staff_new_application(application, staff_email)
    applicant = QueuedMail.applicant_recipient_for(application)
    @user = applicant
    @organization = organization_name
    @application_url = membership_application_url(application)

    extra_vars = { application_url: @application_url }

    if send_from_template('staff_new_application', applicant, extra_vars, to: staff_email)
      # Email sent from database template
    else
      mail(
        to: staff_email,
        subject: "#{@organization}: New application needs review — #{applicant.display_name}"
      )
    end
  end

  # Remind ED / Associate ED trained staff about stale pending applications.
  def staff_application_nag(application, staff_email)
    applicant = QueuedMail.applicant_recipient_for(application)
    @user = applicant
    @organization = organization_name
    @application_url = membership_application_url(application)
    @application_age_days = application_age_days(application)
    @submitted_at = application.submitted_at || application.created_at

    extra_vars = {
      application_url: @application_url,
      application_age_days: @application_age_days.to_s,
      submitted_at: @submitted_at.to_date.to_fs(:long)
    }

    if send_from_template('staff_application_nag', applicant, extra_vars, to: staff_email)
      # Email sent from database template
    else
      mail(
        to: staff_email,
        subject: "#{@organization}: Application overdue for review - #{applicant.display_name}"
      )
    end
  end

  def message_received(message)
    @message = message
    @sender = message.sender
    @recipient = message.recipient
    @organization = organization_name

    mail(
      to: @recipient.email,
      subject: "#{@organization}: Message from #{@sender.display_name} - #{message.subject}"
    )
  end

  # Build template variables for a user, merging in action-specific extras.
  # Public class method so QueuedMail can call it for regeneration.
  def self.build_template_variables(user, extra_args = {})
    vars = base_template_variables(user)
    merge_template_extras!(vars, extra_args)
    vars
  end

  def self.base_template_variables(user)
    org = ENV.fetch('ORGANIZATION_NAME', 'Member Manager')
    {
      member_name: user.display_name,
      member_email: user.email || 'Not provided',
      member_username: user.username || 'Not set',
      organization_name: org,
      date: Date.current.strftime('%B %d, %Y'),
      app_url: ENV.fetch('APP_BASE_URL', 'http://localhost:3000')
    }
  end

  def self.merge_template_extras!(vars, extra_args)
    vars[:days_overdue] = extra_args[:days_overdue] ? " by #{extra_args[:days_overdue]} days" : ''
    vars[:reason] = if extra_args[:reason].present?
                      "<p><strong>Reason:</strong> #{extra_args[:reason]}</p>"
                    else
                      ''
                    end
    vars[:training_topic] = extra_args[:training_topic] if extra_args[:training_topic].present?
    vars[:application_url] = extra_args[:application_url].to_s if extra_args.key?(:application_url)
    merge_training_request_template_keys!(vars, extra_args)
    merge_parking_notice_template_keys!(vars, extra_args)
  end

  def self.merge_training_request_template_keys!(vars, extra_args)
    vars[:requester_name] = extra_args[:requester_name].to_s if extra_args.key?(:requester_name)
    vars[:requester_email] = extra_args[:requester_email].to_s if extra_args.key?(:requester_email)
    vars[:requester_slack] = extra_args[:requester_slack].to_s if extra_args.key?(:requester_slack)
    vars[:recipient_role] = extra_args[:recipient_role].to_s if extra_args.key?(:recipient_role)
    vars[:trainer_names] = extra_args[:trainer_names].to_s if extra_args.key?(:trainer_names)
    vars[:contact_details] = extra_args[:contact_details].to_s if extra_args.key?(:contact_details)
  end

  def self.merge_parking_notice_template_keys!(vars, extra_args)
    vars[:location] = extra_args[:location].to_s if extra_args.key?(:location)
    vars[:location_detail] = extra_args[:location_detail].to_s if extra_args.key?(:location_detail)
    vars[:description] = extra_args[:description].to_s if extra_args.key?(:description)
    vars[:expires_at] = extra_args[:expires_at].to_s if extra_args.key?(:expires_at)
    vars[:notice_type] = extra_args[:notice_type].to_s if extra_args.key?(:notice_type)
  end

  class << self
    private :base_template_variables, :merge_template_extras!, :merge_training_request_template_keys!,
            :merge_parking_notice_template_keys!
  end

  private

  def assign_training_requested_instance_vars(user, opts)
    normalized = normalize_training_requested_opts(opts)
    @user = user
    @organization = organization_name
    @training_topic = normalized[:training_topic]
    @requester_name = normalized[:requester_name] || @user.display_name
    @requester_email = normalized[:requester_email] || @user.email.to_s
    @requester_slack = normalized[:requester_slack] || @user.slack_handle.to_s
    @share_contact_info = ActiveModel::Type::Boolean.new.cast(normalized[:share_contact_info])
    @recipient_role = normalized[:recipient_role] || 'trainer'
    @trainer_names = normalized[:trainer_names] || ''
  end

  def training_requested_template_vars
    {
      training_topic: @training_topic,
      requester_name: @requester_name,
      requester_email: @requester_email,
      requester_slack: @requester_slack,
      recipient_role: @recipient_role,
      trainer_names: @trainer_names,
      contact_details: training_requested_contact_block
    }
  end

  def training_requested_contact_block
    return 'The member did not consent to sharing contact details.' unless @share_contact_info

    [
      ("Email: #{@requester_email}" if @requester_email.present?),
      ("Slack: #{@requester_slack}" if @requester_slack.present?)
    ].compact.join('<br>')
  end

  def training_requested_to_address(user, opts)
    normalized = normalize_training_requested_opts(opts)
    normalized[:to] || user.email
  end

  def normalize_training_requested_opts(opts)
    opts.to_h.deep_symbolize_keys
  end

  def send_from_template(template_key, user, extra_variables = {}, mail_options = {})
    template = EmailTemplate.find_enabled(template_key)
    return false unless template

    variables = build_variables(user).merge(extra_variables)
    rendered = template.render(variables)

    to_address = mail_options[:to] || user.email
    return false if to_address.blank?

    mail(to: to_address, subject: rendered[:subject]) do |format|
      format.html { render html: rendered[:body_html].html_safe, layout: 'mailer' }
      format.text { render plain: rendered[:body_text] }
    end

    true
  end

  def build_variables(user)
    {
      member_name: user.display_name,
      member_email: user.email || 'Not provided',
      member_username: user.username || 'Not set',
      organization_name: organization_name,
      date: Date.current.strftime('%B %d, %Y'),
      app_url: ENV.fetch('APP_BASE_URL', 'http://localhost:3000')
    }
  end

  def membership_applications_fallback_url
    membership_applications_url
  rescue ArgumentError, ActionController::UrlGenerationError
    base = ENV.fetch('APP_BASE_URL', 'http://localhost:3000').chomp('/')
    "#{base}/membership_applications"
  end

  def application_age_days(application)
    start_at = application.submitted_at || application.created_at
    ((Time.current - start_at) / 1.day).floor
  end

  def send_parking_notice_mail(template_key, user, opts = {})
    @user = user
    @organization = organization_name

    extra_vars = {
      location: opts[:location].to_s,
      location_detail: opts[:location_detail].to_s,
      description: opts[:description].to_s,
      expires_at: opts[:expires_at].to_s,
      notice_type: opts[:notice_type].to_s
    }

    subject_label = template_key.humanize.titleize
    if send_from_template(template_key, user, extra_vars)
      # Email sent from database template
    else
      mail(
        to: @user.email,
        subject: "#{@organization}: #{subject_label}"
      )
    end
  end
end
# rubocop:enable Metrics/ClassLength
