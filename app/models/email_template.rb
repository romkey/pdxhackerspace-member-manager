class EmailTemplate < ApplicationRecord
  # Template variable definitions with descriptions
  AVAILABLE_VARIABLES = {
    '{{member_name}}' => 'Full name of the member',
    '{{member_email}}' => 'Email address of the member',
    '{{member_username}}' => 'Username of the member',
    '{{organization_name}}' => 'Name of the organization',
    '{{date}}' => 'Current date',
    '{{days_overdue}}' => 'Number of days payment is overdue (payment emails only)',
    '{{reason}}' => 'Reason for action (cancellation/ban emails only)',
    '{{app_url}}' => 'Base URL of the application'
  }.freeze

  # Default templates that can be seeded
  DEFAULT_TEMPLATES = {
    'application_received' => {
      name: 'Application Received',
      description: 'Sent when a new member application is submitted',
      subject: '{{organization_name}}: Application Received',
      body_html: <<~HTML,
        <h1>Application Received</h1>
        <p>Hello {{member_name}},</p>
        <p>Thank you for applying to join {{organization_name}}!</p>
        <p>We have received your application and it is now being reviewed by our team. You will receive another email once your application has been processed.</p>
        <p>If you have any questions in the meantime, please don't hesitate to reach out.</p>
        <p>Best regards,<br>The {{organization_name}} Team</p>
      HTML
      body_text: <<~TEXT
        Application Received

        Hello {{member_name}},

        Thank you for applying to join {{organization_name}}!

        We have received your application and it is now being reviewed by our team. You will receive another email once your application has been processed.

        If you have any questions in the meantime, please don't hesitate to reach out.

        Best regards,
        The {{organization_name}} Team
      TEXT
    },
    'application_approved' => {
      name: 'Application Approved',
      description: 'Sent when a member application is approved',
      subject: '{{organization_name}}: Welcome! Your Application Has Been Approved',
      body_html: <<~HTML,
        <h1>Welcome to {{organization_name}}!</h1>
        <p>Hello {{member_name}},</p>
        <p><strong>Congratulations!</strong> Your application has been approved and you are now a member of {{organization_name}}.</p>
        <p>Here's what happens next:</p>
        <ul>
          <li>You can now access member-only resources and spaces</li>
          <li>Please make sure your payment method is set up to keep your membership active</li>
          <li>Review our community guidelines and safety policies</li>
        </ul>
        <p>We're excited to have you as part of our community!</p>
        <p>Best regards,<br>The {{organization_name}} Team</p>
      HTML
      body_text: <<~TEXT
        Welcome to {{organization_name}}!

        Hello {{member_name}},

        Congratulations! Your application has been approved and you are now a member of {{organization_name}}.

        Here's what happens next:

        - You can now access member-only resources and spaces
        - Please make sure your payment method is set up to keep your membership active
        - Review our community guidelines and safety policies

        We're excited to have you as part of our community!

        Best regards,
        The {{organization_name}} Team
      TEXT
    },
    'payment_past_due' => {
      name: 'Payment Past Due',
      description: 'Sent when a member payment is overdue',
      subject: '{{organization_name}}: Payment Reminder',
      body_html: <<~HTML,
        <h1>Payment Reminder</h1>
        <p>Hello {{member_name}},</p>
        <p>This is a friendly reminder that your {{organization_name}} membership payment is past due{{days_overdue}}.</p>
        <p>To keep your membership active and maintain access to our facilities and resources, please update your payment information or make a payment as soon as possible.</p>
        <p>If you're experiencing difficulties or need to discuss payment arrangements, please contact us — we're here to help.</p>
        <p>Thank you for being part of our community!</p>
        <p>Best regards,<br>The {{organization_name}} Team</p>
      HTML
      body_text: <<~TEXT
        Payment Reminder

        Hello {{member_name}},

        This is a friendly reminder that your {{organization_name}} membership payment is past due{{days_overdue}}.

        To keep your membership active and maintain access to our facilities and resources, please update your payment information or make a payment as soon as possible.

        If you're experiencing difficulties or need to discuss payment arrangements, please contact us — we're here to help.

        Thank you for being part of our community!

        Best regards,
        The {{organization_name}} Team
      TEXT
    },
    'membership_cancelled' => {
      name: 'Membership Cancelled',
      description: 'Sent when a membership is cancelled',
      subject: '{{organization_name}}: Membership Cancelled',
      body_html: <<~HTML,
        <h1>Membership Cancelled</h1>
        <p>Hello {{member_name}},</p>
        <p>This email confirms that your membership with {{organization_name}} has been cancelled.</p>
        {{reason}}
        <p>Your access to member-only facilities and resources has been deactivated.</p>
        <p>If you believe this was done in error, or if you'd like to rejoin in the future, please contact us.</p>
        <p>Thank you for being part of our community.</p>
        <p>Best regards,<br>The {{organization_name}} Team</p>
      HTML
      body_text: <<~TEXT
        Membership Cancelled

        Hello {{member_name}},

        This email confirms that your membership with {{organization_name}} has been cancelled.

        {{reason}}

        Your access to member-only facilities and resources has been deactivated.

        If you believe this was done in error, or if you'd like to rejoin in the future, please contact us.

        Thank you for being part of our community.

        Best regards,
        The {{organization_name}} Team
      TEXT
    },
    'membership_banned' => {
      name: 'Membership Banned',
      description: 'Sent when a member is banned',
      subject: '{{organization_name}}: Account Suspended',
      body_html: <<~HTML,
        <h1>Account Suspended</h1>
        <p>Hello {{member_name}},</p>
        <p>We regret to inform you that your membership with {{organization_name}} has been suspended.</p>
        {{reason}}
        <p>Your access to all member facilities and resources has been immediately revoked.</p>
        <p>If you wish to appeal this decision or have questions, please contact our administration team.</p>
        <p>Regards,<br>The {{organization_name}} Team</p>
      HTML
      body_text: <<~TEXT
        Account Suspended

        Hello {{member_name}},

        We regret to inform you that your membership with {{organization_name}} has been suspended.

        {{reason}}

        Your access to all member facilities and resources has been immediately revoked.

        If you wish to appeal this decision or have questions, please contact our administration team.

        Regards,
        The {{organization_name}} Team
      TEXT
    },
    'admin_new_application' => {
      name: 'Admin: New Application',
      description: 'Sent to admins when a new application is submitted',
      subject: '{{organization_name}}: New Member Application - {{member_name}}',
      body_html: <<~HTML,
        <h1>New Member Application</h1>
        <p>A new member application has been submitted.</p>
        <h2>Applicant Details</h2>
        <table style="border-collapse: collapse; width: 100%;">
          <tr>
            <td style="padding: 8px; border-bottom: 1px solid #ddd;"><strong>Name:</strong></td>
            <td style="padding: 8px; border-bottom: 1px solid #ddd;">{{member_name}}</td>
          </tr>
          <tr>
            <td style="padding: 8px; border-bottom: 1px solid #ddd;"><strong>Email:</strong></td>
            <td style="padding: 8px; border-bottom: 1px solid #ddd;">{{member_email}}</td>
          </tr>
          <tr>
            <td style="padding: 8px; border-bottom: 1px solid #ddd;"><strong>Username:</strong></td>
            <td style="padding: 8px; border-bottom: 1px solid #ddd;">{{member_username}}</td>
          </tr>
        </table>
        <p style="margin-top: 20px;">Please review this application and take appropriate action.</p>
      HTML
      body_text: <<~TEXT
        New Member Application

        A new member application has been submitted.

        Applicant Details
        -----------------
        Name: {{member_name}}
        Email: {{member_email}}
        Username: {{member_username}}

        Please review this application and take appropriate action.
      TEXT
    }
  }.freeze

  validates :key, presence: true, uniqueness: true
  validates :name, presence: true
  validates :subject, presence: true
  validates :body_html, presence: true
  validates :body_text, presence: true

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(:name) }

  # Find a template by key, returns nil if not found or disabled
  def self.find_enabled(key)
    find_by(key: key, enabled: true)
  end

  # Render the template with given variables
  def render(variables = {})
    {
      subject: substitute_variables(subject, variables),
      body_html: substitute_variables(body_html, variables),
      body_text: substitute_variables(body_text, variables)
    }
  end

  # Preview the template with sample data
  def preview
    sample_variables = {
      member_name: 'John Doe',
      member_email: 'john.doe@example.com',
      member_username: 'johndoe',
      organization_name: ENV.fetch('ORGANIZATION_NAME', 'Member Manager'),
      date: Date.current.strftime('%B %d, %Y'),
      days_overdue: ' by 14 days',
      reason: '<p><strong>Reason:</strong> Example reason</p>',
      app_url: ENV.fetch('APP_BASE_URL', 'http://localhost:3000')
    }
    render(sample_variables)
  end

  # Seed default templates
  def self.seed_defaults!
    DEFAULT_TEMPLATES.each do |key, attrs|
      find_or_create_by!(key: key) do |template|
        template.assign_attributes(attrs)
      end
    end
  end

  private

  def substitute_variables(text, variables)
    result = text.dup
    variables.each do |key, value|
      result.gsub!("{{#{key}}}", value.to_s)
    end
    # Remove any remaining unreplaced variables
    result.gsub!(/\{\{[^}]+\}\}/, '')
    result
  end
end
