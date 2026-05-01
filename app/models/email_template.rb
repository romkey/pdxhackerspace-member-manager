class EmailTemplate < ApplicationRecord
  # Template variable definitions with descriptions
  AVAILABLE_VARIABLES = {
    '{{member_name}}' => 'Full name of the member',
    '{{member_email}}' => 'Email address of the member',
    '{{member_username}}' => 'Username of the member',
    '{{organization_name}}' => 'Name of the organization',
    '{{date}}' => 'Current date',
    '{{days_overdue}}' => 'Number of days payment is overdue (payment emails only)',
    '{{reason}}' => 'Reason for action (cancellation, ban, or application rejection emails)',
    '{{app_url}}' => 'Base URL of the application',
    '{{training_topic}}' => 'Name of the training topic (training emails only)',
    '{{invitation_url}}' => 'URL for the invitation to create an account (invitation emails only)',
    '{{invitation_expiry}}' => 'When the invitation expires (invitation emails only)',
    '{{invitation_type}}' => 'Type of membership being offered, e.g. Sponsored Member (invitation emails only)',
    '{{invitation_type_details}}' => 'Description of what the membership type includes (invitation emails only)',
    '{{application_url}}' => 'Direct link to the membership application ' \
                             '(admin new application & staff alert templates)',
    '{{application_age_days}}' => 'How many days a membership application has been pending',
    '{{submitted_at}}' => 'Date the membership application was submitted',
    '{{requester_name}}' => 'Name of the member who requested training',
    '{{requester_email}}' => 'Email address of the member requesting training (if shared)',
    '{{requester_slack}}' => 'Slack handle of the member requesting training (if shared)',
    '{{recipient_role}}' => 'Whether this notification is for a member or trainer',
    '{{trainer_names}}' => 'Comma-separated trainer names notified for a request',
    '{{contact_details}}' => 'Rendered contact details block for training request notifications'
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
    'application_rejected' => {
      name: 'Application Rejected',
      description: 'Sent when a membership application is rejected',
      subject: '{{organization_name}}: Update on Your Membership Application',
      body_html: <<~HTML,
        <h1>Application Not Approved</h1>
        <p>Hello {{member_name}},</p>
        <p>Thank you for your interest in joining {{organization_name}}. After careful review, we are not able to approve your membership application at this time.</p>
        {{reason}}
        <p>If you have questions or believe this decision was made in error, please contact us.</p>
        <p>Best regards,<br>The {{organization_name}} Team</p>
      HTML
      body_text: <<~TEXT
        Application Not Approved

        Hello {{member_name}},

        Thank you for your interest in joining {{organization_name}}. After careful review, we are not able to approve your membership application at this time.

        {{reason}}

        If you have questions or believe this decision was made in error, please contact us.

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
    'membership_lapsed' => {
      name: 'Membership Lapsed',
      description: 'Sent when a member\'s dues have lapsed',
      subject: '{{organization_name}}: Your Membership Dues Have Lapsed',
      body_html: <<~HTML,
        <h1>Membership Dues Lapsed</h1>
        <p>Hello {{member_name}},</p>
        <p>We're writing to let you know that your {{organization_name}} membership dues have lapsed. Your access to member facilities and resources may be affected.</p>
        <p>To restore your membership, please update your payment information or make a payment at your earliest convenience.</p>
        <p>If you're experiencing difficulties or have questions about your membership, please don't hesitate to reach out — we're happy to help.</p>
        <p>Thank you for being part of our community.</p>
        <p>Best regards,<br>The {{organization_name}} Team</p>
      HTML
      body_text: <<~TEXT
        Membership Dues Lapsed

        Hello {{member_name}},

        We're writing to let you know that your {{organization_name}} membership dues have lapsed. Your access to member facilities and resources may be affected.

        To restore your membership, please update your payment information or make a payment at your earliest convenience.

        If you're experiencing difficulties or have questions about your membership, please don't hesitate to reach out — we're happy to help.

        Thank you for being part of our community.

        Best regards,
        The {{organization_name}} Team
      TEXT
    },
    'membership_sponsored' => {
      name: 'Membership Sponsored',
      description: 'Sent when a member receives a sponsored membership',
      subject: '{{organization_name}}: Your Membership Has Been Sponsored!',
      body_html: <<~HTML,
        <h1>Your Membership Has Been Sponsored!</h1>
        <p>Hello {{member_name}},</p>
        <p>Great news! Your membership with {{organization_name}} has been sponsored. This means your membership dues are covered and you can continue to enjoy all member benefits.</p>
        <p>Your access to all member facilities and resources remains fully active.</p>
        <p>If you have any questions about your sponsored membership, please don't hesitate to contact us.</p>
        <p>Best regards,<br>The {{organization_name}} Team</p>
      HTML
      body_text: <<~TEXT
        Your Membership Has Been Sponsored!

        Hello {{member_name}},

        Great news! Your membership with {{organization_name}} has been sponsored. This means your membership dues are covered and you can continue to enjoy all member benefits.

        Your access to all member facilities and resources remains fully active.

        If you have any questions about your sponsored membership, please don't hesitate to contact us.

        Best regards,
        The {{organization_name}} Team
      TEXT
    },
    'admin_new_application' => {
      name: 'Admin: New Application',
      description: 'Admin notice for new applications; includes {{application_url}} (detail page or list fallback).',
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
        <p style="margin-top: 20px;"><a href="{{application_url}}">Open this application in Member Manager</a></p>
        <p>Please review this application and take appropriate action.</p>
      HTML
      body_text: <<~TEXT
        New Member Application

        A new member application has been submitted.

        Applicant Details
        -----------------
        Name: {{member_name}}
        Email: {{member_email}}
        Username: {{member_username}}

        Open in Member Manager: {{application_url}}

        Please review this application and take appropriate action.
      TEXT
    },
    'staff_new_application' => {
      name: 'Staff: New Application (immediate)',
      description: 'Immediate alert to executive application review staff when an application is submitted',
      subject: '{{organization_name}}: New application needs review — {{member_name}}',
      body_html: <<~HTML,
        <h1>New membership application</h1>
        <p>A new membership application has been submitted and needs to be processed.</p>
        <h2>Applicant</h2>
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
        <p style="margin-top: 20px;"><a href="{{application_url}}">Open this application in Member Manager</a></p>
      HTML
      body_text: <<~TEXT
        New membership application

        A new membership application has been submitted and needs to be processed.

        Applicant
        ---------
        Name: {{member_name}}
        Email: {{member_email}}
        Username: {{member_username}}

        Open in Member Manager: {{application_url}}
      TEXT
    },
    'staff_application_nag' => {
      name: 'Staff: Application Reminder',
      description: 'Reminder to ED / Associate ED trained staff when an application is pending after one week',
      subject: '{{organization_name}}: Application overdue for review - {{member_name}}',
      body_html: <<~HTML,
        <h1>Membership application needs review</h1>
        <p>This membership application has been pending for {{application_age_days}} days.</p>
        <h2>Applicant</h2>
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
            <td style="padding: 8px; border-bottom: 1px solid #ddd;"><strong>Submitted:</strong></td>
            <td style="padding: 8px; border-bottom: 1px solid #ddd;">{{submitted_at}}</td>
          </tr>
        </table>
        <p style="margin-top: 20px;"><a href="{{application_url}}">Open this application in Member Manager</a></p>
        <p>Please accept, reject, or move this application along.</p>
      HTML
      body_text: <<~TEXT
        Membership application needs review

        This membership application has been pending for {{application_age_days}} days.

        Applicant
        ---------
        Name: {{member_name}}
        Email: {{member_email}}
        Submitted: {{submitted_at}}

        Open in Member Manager: {{application_url}}

        Please accept, reject, or move this application along.
      TEXT
    },
    'training_requested' => {
      name: 'Training Requested',
      description: 'Sent when a member requests training in a topic',
      subject: '{{organization_name}}: Training request for {{training_topic}}',
      body_html: <<~HTML,
        <h1>Training Request: {{training_topic}}</h1>
        <p>Hello {{member_name}},</p>
        <p>A training request has been submitted for <strong>{{training_topic}}</strong>.</p>
        <p><strong>Recipient role:</strong> {{recipient_role}}</p>
        <h2>Requester details</h2>
        <ul>
          <li><strong>Name:</strong> {{requester_name}}</li>
          <li><strong>Email:</strong> {{requester_email}}</li>
          <li><strong>Slack:</strong> {{requester_slack}}</li>
        </ul>
        <p>{{contact_details}}</p>
        <p>Trainers notified: {{trainer_names}}</p>
        <p>You can respond in Member Manager from your profile dashboard.</p>
      HTML
      body_text: <<~TEXT
        Training Request: {{training_topic}}

        Hello {{member_name}},

        A training request has been submitted for {{training_topic}}.
        Recipient role: {{recipient_role}}

        Requester details:
        - Name: {{requester_name}}
        - Email: {{requester_email}}
        - Slack: {{requester_slack}}

        {{contact_details}}

        Trainers notified: {{trainer_names}}

        You can respond in Member Manager from your profile dashboard.
      TEXT
    },
    'training_completed' => {
      name: 'Training Completed',
      description: 'Sent when a member completes training on a topic',
      subject: '{{organization_name}}: You\'re Now Trained in {{training_topic}}!',
      body_html: <<~HTML,
        <h1>Training Complete: {{training_topic}}</h1>
        <p>Hello {{member_name}},</p>
        <p>Congratulations! You've been marked as trained in <strong>{{training_topic}}</strong> at {{organization_name}}.</p>
        <p>You now have access to the equipment, resources, and spaces associated with this training. Any related documentation and links are available on your profile page under your training section.</p>
        <p>Please remember to follow all safety guidelines and operating procedures. If you have any questions, don't hesitate to ask a trainer or staff member.</p>
        <p>Happy making!</p>
        <p>Best regards,<br>The {{organization_name}} Team</p>
      HTML
      body_text: <<~TEXT
        Training Complete: {{training_topic}}

        Hello {{member_name}},

        Congratulations! You've been marked as trained in {{training_topic}} at {{organization_name}}.

        You now have access to the equipment, resources, and spaces associated with this training. Any related documentation and links are available on your profile page under your training section.

        Please remember to follow all safety guidelines and operating procedures. If you have any questions, don't hesitate to ask a trainer or staff member.

        Happy making!

        Best regards,
        The {{organization_name}} Team
      TEXT
    },
    'member_invitation' => {
      name: 'Member Invitation',
      description: 'Sent to invite someone to create a new member account',
      subject: '{{organization_name}}: You\'re Invited to Join as a {{invitation_type}}!',
      body_html: <<~HTML,
        <h1>You're Invited!</h1>
        <p>Hello,</p>
        <p>You've been invited to join <strong>{{organization_name}}</strong> as a <strong>{{invitation_type}}</strong>.</p>
        <p>{{invitation_type_details}}</p>
        <p>Click the link below to get started:</p>
        <p><a href="{{invitation_url}}" style="display: inline-block; padding: 12px 24px; background-color: #0d6efd; color: #ffffff; text-decoration: none; border-radius: 6px; font-weight: bold;">Create Your Account</a></p>
        <p>Or copy and paste this URL into your browser:</p>
        <p>{{invitation_url}}</p>
        <p><em>This invitation expires {{invitation_expiry}}.</em></p>
        <p>If you have any questions, please reach out to us.</p>
        <p>Best regards,<br>The {{organization_name}} Team</p>
      HTML
      body_text: <<~TEXT
        You're Invited!

        Hello,

        You've been invited to join {{organization_name}} as a {{invitation_type}}.

        {{invitation_type_details}}

        Click here to get started: {{invitation_url}}

        This invitation expires {{invitation_expiry}}.

        If you have any questions, please reach out to us.

        Best regards,
        The {{organization_name}} Team
      TEXT
    },
    'trainer_capability_granted' => {
      name: 'Trainer Capability Granted',
      description: 'Sent when a member is granted the ability to train others',
      subject: '{{organization_name}}: You Can Now Train Others in {{training_topic}}!',
      body_html: <<~HTML,
        <h1>You're a Trainer: {{training_topic}}</h1>
        <p>Hello {{member_name}},</p>
        <p>Great news! You've been granted the ability to train other members in <strong>{{training_topic}}</strong> at {{organization_name}}.</p>
        <p>As a trainer, you can mark members as trained once they've completed their training with you. To do this:</p>
        <ol>
          <li>Go to the <strong>Train a Member</strong> page from the dashboard</li>
          <li>Search for the member you've trained</li>
          <li>Select <strong>{{training_topic}}</strong> and mark them as trained</li>
        </ol>
        <p>Thank you for helping grow our community's skills!</p>
        <p>Best regards,<br>The {{organization_name}} Team</p>
      HTML
      body_text: <<~TEXT
        You're a Trainer: {{training_topic}}

        Hello {{member_name}},

        Great news! You've been granted the ability to train other members in {{training_topic}} at {{organization_name}}.

        As a trainer, you can mark members as trained once they've completed their training with you. To do this:

        1. Go to the Train a Member page from the dashboard
        2. Search for the member you've trained
        3. Select {{training_topic}} and mark them as trained

        Thank you for helping grow our community's skills!

        Best regards,
        The {{organization_name}} Team
      TEXT
    }
  }.freeze

  validates :key, presence: true, uniqueness: true
  validates :name, presence: true
  validates :subject, presence: true
  validates :body_html, presence: true
  validates :body_text, presence: true

  before_validation :clear_send_immediately_if_blocked

  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }
  scope :needs_review, -> { where(needs_review: true) }
  scope :reviewed, -> { where(needs_review: false) }
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
      app_url: ENV.fetch('APP_BASE_URL', 'http://localhost:3000'),
      training_topic: 'Laser Cutter',
      invitation_url: "#{ENV.fetch('APP_BASE_URL', 'http://localhost:3000')}/invite/sample-token-abc123",
      invitation_expiry: 'in 3 days',
      invitation_type: 'Sponsored Member',
      invitation_type_details: 'Sponsored membership — full access including building access, no dues required.',
      application_url: "#{ENV.fetch('APP_BASE_URL', 'http://localhost:3000')}/membership_applications/1",
      application_age_days: '8',
      submitted_at: 8.days.ago.to_date.to_fs(:long),
      requester_name: 'Alex Example',
      requester_email: 'alex@example.com',
      requester_slack: '@alex',
      recipient_role: 'trainer',
      trainer_names: 'Trainer One, Trainer Two',
      contact_details: 'Email: alex@example.com'
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

  def clear_send_immediately_if_blocked
    self.send_immediately = false if block_send_immediately?
  end

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
