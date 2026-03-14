# Mailer for member-related notifications
# Uses database templates when available, falls back to view templates
class MemberMailer < ApplicationMailer
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

  # Notify admins of a new application
  def admin_new_application(user, admin_email)
    @user = user
    @organization = organization_name
    @admin_email = admin_email

    if send_from_template('admin_new_application', user, {}, to: admin_email)
      # Email sent from database template
    else
      mail(
        to: admin_email,
        subject: "#{@organization}: New Member Application - #{@user.display_name}"
      )
    end
  end

  # Build template variables for a user, merging in action-specific extras.
  # Public class method so QueuedMail can call it for regeneration.
  def self.build_template_variables(user, extra_args = {})
    org = ENV.fetch('ORGANIZATION_NAME', 'Member Manager')
    vars = {
      member_name: user.display_name,
      member_email: user.email || 'Not provided',
      member_username: user.username || 'Not set',
      organization_name: org,
      date: Date.current.strftime('%B %d, %Y'),
      app_url: ENV.fetch('APP_BASE_URL', 'http://localhost:3000')
    }

    vars[:days_overdue] = if extra_args[:days_overdue]
                            " by #{extra_args[:days_overdue]} days"
                          else
                            ''
                          end

    vars[:reason] = if extra_args[:reason].present?
                      "<p><strong>Reason:</strong> #{extra_args[:reason]}</p>"
                    else
                      ''
                    end

    vars[:training_topic] = extra_args[:training_topic] if extra_args[:training_topic].present?

    # Parking notice variables
    vars[:location] = extra_args[:location].to_s if extra_args.key?(:location)
    vars[:location_detail] = extra_args[:location_detail].to_s if extra_args.key?(:location_detail)
    vars[:description] = extra_args[:description].to_s if extra_args.key?(:description)
    vars[:expires_at] = extra_args[:expires_at].to_s if extra_args.key?(:expires_at)
    vars[:notice_type] = extra_args[:notice_type].to_s if extra_args.key?(:notice_type)

    vars
  end

  private

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
