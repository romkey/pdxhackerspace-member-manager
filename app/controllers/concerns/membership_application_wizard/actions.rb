# frozen_string_literal: true

module MembershipApplicationWizard
  # Public HTTP actions for the apply flow.
  module Actions
    extend ActiveSupport::Concern

    included do
      before_action :require_verified_email!, only: %i[start save_page page submit_application]
      before_action :load_pages, only: %i[start page]
    end

    def start
      @intro_content = TextFragment.content_for('application_form_intro')
      @verification = current_verification
      @email = @verification&.email

      @application = find_in_progress_application
      if @application.nil? && @email
        draft = MembershipApplication.find_by(email: @email, status: 'draft')
        if draft
          session[:application_token] = draft.token
          @application = draft
        end
      end

      return unless @email

      @existing_application = MembershipApplication.where(email: @email)
                                                   .where.not(status: 'draft')
                                                   .newest_first
                                                   .first
    end

    def save_page
      page_number = params[:page_number].to_i

      if page_number.zero?
        save_email_page
      else
        save_question_page(page_number)
      end
    end

    def page
      @application = find_in_progress_application
      unless @application
        redirect_to apply_start_path, alert: 'Please start your application to continue.'
        return
      end

      page_number = params[:page_number].to_i
      @current_page = @pages[page_number - 1]
      unless @current_page
        redirect_to apply_start_path
        return
      end

      @page_number = page_number
      @questions = @current_page.questions.ordered
    end

    def submit_application
      @application = find_in_progress_application
      unless @application&.draft?
        redirect_to apply_start_path, alert: 'No application in progress.'
        return
      end

      missing = check_required_fields
      if missing.any?
        redirect_to apply_page_path(page_number: missing.first[:page_number]),
                    alert: 'Please complete required fields before submitting.'
        return
      end

      @application.submit!
      session.delete(:application_token)
      redirect_to apply_confirmation_path
    end

    def confirmation; end
  end
end
