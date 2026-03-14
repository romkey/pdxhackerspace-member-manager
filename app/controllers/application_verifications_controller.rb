class ApplicationVerificationsController < ApplicationController
  def gate
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
    unless params[:confirmed_open_house] == '1'
      redirect_to apply_new_path, alert: 'You must confirm that you have attended an open house.'
      return
    end

    unless params[:confirmed_code_of_conduct] == '1'
      redirect_to apply_new_path, alert: 'You must confirm that you have read and agree with the Code of Conduct.'
      return
    end

    email = params[:email].to_s.strip.downcase
    if email.blank? || !email.match?(URI::MailTo::EMAIL_REGEXP)
      redirect_to apply_new_path, alert: 'Please enter a valid email address.'
      return
    end

    verification = ApplicationVerification.create!(
      email: email,
      confirmed_open_house: true,
      confirmed_code_of_conduct: true
    )

    verification_url = apply_verify_email_url(token: verification.token)
    expiry_hours = MembershipSetting.application_verification_expiry_hours

    MemberMailer.application_email_verification(
      email,
      verification_url: verification_url,
      expires_in: "#{expiry_hours} #{'hour'.pluralize(expiry_hours)}"
    ).deliver_later

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
end
