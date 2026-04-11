class ApplicationVerificationsController < ApplicationController
  before_action :redirect_builtin_only_requests_when_external, only: %i[send_verification verify_email check_email]

  def gate
    unless MembershipSetting.use_builtin_membership_application?
      @apply_content = TextFragment.content_for('apply_for_membership')
      render :gate_external
      return
    end

    @code_of_conduct_doc = Document.find_by('LOWER(title) = ?', 'code of conduct')
  end

  def code_of_conduct_pdf
    doc = Document.find_by('LOWER(title) = ?', 'code of conduct')
    if doc&.file&.attached?
      send_data doc.file.download,
                filename: doc.file.filename.to_s,
                type: doc.file.content_type,
                disposition: 'inline'
    else
      head :not_found
    end
  end

  def send_verification
    return unless open_house_confirmation_ok?
    return unless code_of_conduct_confirmation_ok?

    email = normalized_verification_email
    return if email.nil?

    verification = create_verification!(email)
    deliver_verification_mailer(email, verification)

    redirect_to apply_check_email_path
  end

  def verify_email
    verification = ApplicationVerification.find_by(token: params[:token])

    if verification.nil?
      redirect_to apply_new_path, alert: 'Invalid verification link.'
      return
    end

    if verification.expired?
      redirect_to apply_new_path, alert: 'This verification link has expired. Please start over.'
      return
    end

    verification.verify_email!
    session[:verified_application_token] = verification.token

    redirect_to apply_start_path
  end

  def check_email; end

  private

  def redirect_builtin_only_requests_when_external
    return if MembershipSetting.use_builtin_membership_application?

    redirect_to apply_path,
                alert: 'Applications use the instructions on the apply page. Follow the link from sign-in to apply.'
  end

  def open_house_confirmation_ok?
    return true if params[:confirmed_open_house] == '1'

    redirect_to apply_new_path, alert: 'You must confirm that you have attended an open house.'
    false
  end

  def code_of_conduct_confirmation_ok?
    return true if params[:confirmed_code_of_conduct] == '1'

    redirect_to apply_new_path, alert: 'You must confirm that you have read and agree with the Code of Conduct.'
    false
  end

  def normalized_verification_email
    email = params[:email].to_s.strip.downcase
    if email.blank? || !email.match?(URI::MailTo::EMAIL_REGEXP)
      redirect_to apply_new_path, alert: 'Please enter a valid email address.'
      return
    end
    email
  end

  def create_verification!(email)
    ApplicationVerification.create!(
      email: email,
      confirmed_open_house: true,
      confirmed_code_of_conduct: true
    )
  end

  def deliver_verification_mailer(email, verification)
    verification_url = apply_verify_email_url(token: verification.token)
    expiry_hours = MembershipSetting.application_verification_expiry_hours

    MemberMailer.application_email_verification(
      email,
      verification_url: verification_url,
      expires_in: "#{expiry_hours} #{'hour'.pluralize(expiry_hours)}"
    ).deliver_later
  end
end
