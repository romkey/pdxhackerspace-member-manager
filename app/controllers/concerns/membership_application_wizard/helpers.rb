# frozen_string_literal: true

module MembershipApplicationWizard
  # Session, verification, and form persistence for the apply flow.
  module Helpers
    extend ActiveSupport::Concern

    private

    def load_pages
      @pages = ApplicationFormPage.ordered.to_a
    end

    def find_in_progress_application
      token = session[:application_token]
      return nil unless token

      MembershipApplication.find_by(token: token, status: 'draft')
    end

    def persist_answers_for_questions!(current_page, answers, answers_other)
      current_page.questions.each do |question|
        value = answers[question.id.to_s].to_s.strip
        if value == 'Other'
          other_value = answers_other[question.id.to_s].to_s.strip
          value = other_value.presence || 'Other'
        end
        answer = @application.application_answers.find_or_initialize_by(
          application_form_question: question
        )
        answer.value = value
        answer.save!
      end
    end

    def redirect_after_saving_page(page_number, page_count)
      next_page = page_number + 1
      if next_page > page_count
        redirect_to apply_page_path(page_number: page_number),
                    notice: 'Answers saved. Review and submit when ready.'
      else
        redirect_to apply_page_path(page_number: next_page)
      end
    end

    def save_email_page
      verification = current_verification
      email = verification.email

      app = MembershipApplication.find_by(email: email, status: 'draft')
      app ||= MembershipApplication.create!(email: email)

      session[:application_token] = app.token
      redirect_to apply_page_path(page_number: 1)
    end

    def save_question_page(page_number)
      @application = find_in_progress_application
      unless @application
        redirect_to apply_start_path, alert: 'Please start your application to continue.'
        return
      end

      pages = ApplicationFormPage.ordered.to_a
      current_page = pages[page_number - 1]
      unless current_page
        redirect_to apply_start_path
        return
      end

      persist_answers_for_questions!(current_page, params[:answers] || {}, params[:answers_other] || {})

      redirect_after_saving_page(page_number, pages.size)
    end

    def check_required_fields
      missing = []
      ApplicationFormPage.ordered.each_with_index do |page, idx|
        page.questions.where(required: true).find_each do |q|
          answer = @application.answer_for(q)
          missing << { page_number: idx + 1, question: q } if answer.nil? || answer.value.blank?
        end
      end
      missing
    end
  end
end
