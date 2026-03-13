class MembershipApplicationsController < ApplicationController
  include Pagy::Backend

  before_action :require_admin!, only: %i[index show approve reject mark_under_review]
  before_action :set_application_admin, only: %i[show approve reject mark_under_review]
  before_action :load_pages, only: %i[start page]

  # --- Public wizard actions ---

  def start
    @intro_content = TextFragment.content_for('application_form_intro')
    @application = find_in_progress_application
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
      redirect_to apply_new_path, alert: 'Please enter your email to begin.'
      return
    end

    page_number = params[:page_number].to_i
    @current_page = @pages[page_number - 1]
    unless @current_page
      redirect_to apply_new_path
      return
    end

    @page_number = page_number
    @questions = @current_page.questions.ordered
  end

  def submit_application
    @application = find_in_progress_application
    unless @application&.draft?
      redirect_to apply_new_path, alert: 'No application in progress.'
      return
    end

    missing = check_required_fields
    if missing.any?
      redirect_to apply_page_path(page_number: missing.first[:page_number]),
                  alert: "Please complete required fields before submitting."
      return
    end

    @application.submit!
    session.delete(:application_token)
    redirect_to apply_confirmation_path
  end

  def confirmation; end

  # --- Admin actions ---

  def index
    @applications = MembershipApplication.where.not(status: 'draft').newest_first
    @applications = @applications.where(status: params[:status]) if params[:status].present?

    @status_counts = {
      all: MembershipApplication.where.not(status: 'draft').count,
      submitted: MembershipApplication.submitted_apps.count,
      under_review: MembershipApplication.under_review.count,
      approved: MembershipApplication.approved.count,
      rejected: MembershipApplication.rejected.count
    }

    @pagy, @applications = pagy(@applications, limit: 25)
  end

  def show
    @pages_with_answers = @application.answers_by_page
  end

  def approve
    notes = params[:admin_notes]
    @application.approve!(current_user, notes: notes)
    redirect_to membership_application_path(@application),
                notice: 'Application approved.'
  end

  def reject
    notes = params[:admin_notes]
    @application.reject!(current_user, notes: notes)
    redirect_to membership_application_path(@application),
                notice: 'Application rejected.'
  end

  def mark_under_review
    @application.mark_under_review!(current_user)
    redirect_to membership_application_path(@application),
                notice: 'Application marked as under review.'
  end

  private

  def load_pages
    @pages = ApplicationFormPage.ordered.to_a
  end

  def find_in_progress_application
    token = session[:application_token]
    return nil unless token

    MembershipApplication.find_by(token: token, status: 'draft')
  end

  def save_email_page
    email = params[:email].to_s.strip.downcase
    if email.blank? || !email.include?('@')
      redirect_to apply_new_path, alert: 'Please enter a valid email address.'
      return
    end

    app = MembershipApplication.find_by(email: email, status: 'draft')
    app ||= MembershipApplication.create!(email: email)

    session[:application_token] = app.token
    redirect_to apply_page_path(page_number: 1)
  end

  def save_question_page(page_number)
    @application = find_in_progress_application
    unless @application
      redirect_to apply_new_path, alert: 'Please enter your email to begin.'
      return
    end

    pages = ApplicationFormPage.ordered.to_a
    current_page = pages[page_number - 1]
    unless current_page
      redirect_to apply_new_path
      return
    end

    answers = params[:answers] || {}
    current_page.questions.each do |question|
      value = answers[question.id.to_s].to_s.strip
      answer = @application.application_answers.find_or_initialize_by(
        application_form_question: question
      )
      answer.value = value
      answer.save!
    end

    next_page = page_number + 1
    if next_page > pages.size
      redirect_to apply_page_path(page_number: page_number),
                  notice: 'Answers saved. Review and submit when ready.'
    else
      redirect_to apply_page_path(page_number: next_page)
    end
  end

  def check_required_fields
    missing = []
    ApplicationFormPage.ordered.each_with_index do |page, idx|
      page.questions.where(required: true).each do |q|
        answer = @application.answer_for(q)
        if answer.nil? || answer.value.blank?
          missing << { page_number: idx + 1, question: q }
        end
      end
    end
    missing
  end

  def set_application_admin
    @application = MembershipApplication.find(params[:id])
  end
end
