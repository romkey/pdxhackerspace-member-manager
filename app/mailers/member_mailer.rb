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
  def membership_cancelled(user, reason: nil)
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
  def membership_banned(user, reason: nil)
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

  private

  # Try to send email from a database template
  # Returns true if sent from template, false if should fall back to view
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
end
