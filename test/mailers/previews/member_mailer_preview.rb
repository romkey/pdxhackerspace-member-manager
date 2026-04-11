# Preview all emails at http://localhost:3000/rails/mailers/member_mailer
class MemberMailerPreview < ActionMailer::Preview
  # Preview at http://localhost:3000/rails/mailers/member_mailer/application_received
  def application_received
    user = User.first || sample_user
    MemberMailer.application_received(user)
  end

  # Preview at http://localhost:3000/rails/mailers/member_mailer/application_approved
  def application_approved
    user = User.first || sample_user
    MemberMailer.application_approved(user)
  end

  # Preview at http://localhost:3000/rails/mailers/member_mailer/application_rejected
  def application_rejected
    user = User.first || sample_user
    MemberMailer.application_rejected(user, reason: 'We are not accepting new members in this category.')
  end

  # Preview at http://localhost:3000/rails/mailers/member_mailer/payment_past_due
  def payment_past_due
    user = User.first || sample_user
    MemberMailer.payment_past_due(user, days_overdue: 14)
  end

  # Preview at http://localhost:3000/rails/mailers/member_mailer/membership_cancelled
  def membership_cancelled
    user = User.first || sample_user
    MemberMailer.membership_cancelled(user, reason: 'Non-payment of dues')
  end

  # Preview at http://localhost:3000/rails/mailers/member_mailer/membership_banned
  def membership_banned
    user = User.first || sample_user
    MemberMailer.membership_banned(user, reason: 'Violation of Code of Conduct')
  end

  def membership_lapsed
    user = User.first || sample_user
    MemberMailer.membership_lapsed(user)
  end

  def membership_sponsored
    user = User.first || sample_user
    MemberMailer.membership_sponsored(user)
  end

  def training_completed
    user = User.first || sample_user
    MemberMailer.training_completed(user, training_topic: 'Laser Cutter')
  end

  def trainer_capability_granted
    user = User.first || sample_user
    MemberMailer.trainer_capability_granted(user, training_topic: 'Laser Cutter')
  end

  # Preview at http://localhost:3000/rails/mailers/member_mailer/admin_new_application
  def admin_new_application
    user = User.first || sample_user
    app = MembershipApplication.order(id: :desc).first
    base = ENV.fetch('APP_BASE_URL', 'http://localhost:3000').chomp('/')
    url = app ? "#{base}/membership_applications/#{app.id}" : "#{base}/membership_applications/1"
    MemberMailer.admin_new_application(user, 'admin@example.com', application_url: url)
  end

  # Preview at http://localhost:3000/rails/mailers/member_mailer/staff_new_application
  def staff_new_application
    app = MembershipApplication.order(id: :desc).first || MembershipApplication.create!(
      email: 'mailer-preview-staff-app@example.com',
      status: 'submitted'
    )
    MemberMailer.staff_new_application(app, 'director@example.com')
  end

  private

  def sample_user
    User.new(
      full_name: 'John Doe',
      email: 'john.doe@example.com',
      username: 'johndoe'
    )
  end
end
