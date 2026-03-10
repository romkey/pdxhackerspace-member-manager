class CreateLoginLinkExpiredEmailTemplate < ActiveRecord::Migration[8.1]
  def up
    EmailTemplate.create!(
      key: 'login_link_expired',
      name: 'Login Link Expired',
      description: 'Sent to a member when their login link has expired.',
      subject: '{{organization_name}}: Your Login Link Has Expired',
      body_html: <<~HTML,
        <p>Hi {{member_name}},</p>
        <p>Your login link for <strong>{{organization_name}}</strong> has expired.</p>
        <p>To generate a new login link, please sign in to your account and visit your profile.</p>
      HTML
      body_text: <<~TEXT,
        Hi {{member_name}},

        Your login link for {{organization_name}} has expired.

        To generate a new login link, please sign in to your account and visit your profile.
      TEXT
      enabled: true,
      needs_review: true
    )
  end

  def down
    EmailTemplate.where(key: 'login_link_expired').destroy_all
  end
end
