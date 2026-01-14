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

  # Preview at http://localhost:3000/rails/mailers/member_mailer/payment_past_due
  def payment_past_due
    user = User.first || sample_user
    MemberMailer.payment_past_due(user, days_overdue: 14)
  end

  # Preview at http://localhost:3000/rails/mailers/member_mailer/membership_cancelled
  def membership_cancelled
    user = User.first || sample_user
    MemberMailer.membership_cancelled(user, reason: "Non-payment of dues")
  end

  # Preview at http://localhost:3000/rails/mailers/member_mailer/membership_banned
  def membership_banned
    user = User.first || sample_user
    MemberMailer.membership_banned(user, reason: "Violation of Code of Conduct")
  end

  # Preview at http://localhost:3000/rails/mailers/member_mailer/admin_new_application
  def admin_new_application
    user = User.first || sample_user
    MemberMailer.admin_new_application(user, "admin@example.com")
  end

  private

  def sample_user
    User.new(
      full_name: "John Doe",
      email: "john.doe@example.com",
      username: "johndoe"
    )
  end
end
