# frozen_string_literal: true

module MembershipApplicationWizard
  module Verification
    extend ActiveSupport::Concern

    private

    def require_verified_email!
      verification = current_verification
      return if verification&.verified?

      redirect_to apply_new_path, alert: 'Please verify your email address before starting an application.'
    end

    def current_verification
      token = session[:verified_application_token]
      return nil unless token

      ApplicationVerification.find_by(token: token)
    end
  end
end
