class MembershipApplicationsController < ApplicationController
  require 'csv'

  include Pagy::Method
  include MembershipApplicationWizard
  include MembershipApplicationWizard::Actions

  ADMIN_ACTIONS = %i[
    index show import approve reject delay_for_review link_user unlink_user vote_ai_feedback
    save_tour_feedback vote_acceptance
  ].freeze
  APPLICATION_MEMBER_ACTIONS = %i[
    show approve reject delay_for_review link_user unlink_user vote_ai_feedback
    save_tour_feedback vote_acceptance
  ].freeze

  before_action :require_admin!, only: ADMIN_ACTIONS
  before_action :set_application_admin, only: APPLICATION_MEMBER_ACTIONS
  before_action :require_executive_director_for_final_decision!, only: %i[approve reject delay_for_review]
  before_action :require_submitted_for_delay!, only: :delay_for_review
  before_action :require_pending_application_for_acceptance_vote!, only: :vote_acceptance

  # --- Admin actions ---

  def import
    if params[:file].blank?
      redirect_to membership_applications_path, alert: 'Please choose a CSV file to import.'
      return
    end

    result = MembershipApplications::CsvImporter.new(imported_by: current_user).call(params[:file])
    notice_parts = ["Imported #{result[:imported]} application(s)."]
    notice_parts << "#{result[:skipped]} row(s) skipped." if result[:skipped].positive?
    if result[:errors].any?
      msg = result[:errors].first(5).join(' ')
      flash[:alert] = result[:errors].size > 5 ? "#{msg} …" : msg
    end
    redirect_to membership_applications_path, notice: notice_parts.join(' ')
  rescue CSV::MalformedCSVError => e
    redirect_to membership_applications_path, alert: "Invalid CSV: #{e.message}"
  end

  def index
    base_scope = MembershipApplication.where.not(status: 'draft')
    @applications = base_scope.includes(:user, :reviewed_by, :application_answers, :acceptance_votes)
    @current_status = params[:status].presence || 'submitted'
    @applications = case @current_status
                    when 'all'
                      @applications
                    when 'unlinked'
                      @applications.where(user_id: nil).where(status: 'approved')
                    else
                      @applications.where(status: @current_status)
                    end
    @applications = @applications.admin_search(params[:q])
    # Ensure stable newest-first order after search/includes (PostgreSQL + AR can otherwise return arbitrary order).
    @applications = @applications.newest_first

    @status_counts = {
      all: MembershipApplication.where.not(status: 'draft').count,
      submitted: MembershipApplication.submitted_apps.count,
      under_review: MembershipApplication.under_review_apps.count,
      approved: MembershipApplication.approved.count,
      rejected: MembershipApplication.rejected.count,
      unlinked: MembershipApplication.where(status: 'approved').where(user_id: nil).count
    }

    @pagy, @applications = pagy(@applications, limit: 25)

    name_q_scope = ApplicationFormQuestion.joins(:application_form_page)
    @applicant_name_question_id = name_q_scope.where(application_form_pages: { position: 1 }, label: 'Name').pick(:id)

    @users_for_application_link = User.non_service_accounts.ordered_by_display_name.to_a
  end

  def show
    @pages_with_answers = @application.answers_by_page
    @users_for_application_link = User.non_service_accounts.ordered_by_display_name.to_a
    vote = @application.ai_feedback_votes.detect { |v| v.user_id == current_user.id }
    @current_ai_feedback_vote = vote || @application.ai_feedback_votes.build(user: current_user)
    tf = @application.tour_feedbacks.detect { |f| f.user_id == current_user.id }
    @current_tour_feedback = tf || @application.tour_feedbacks.build(user: current_user)
    av = @application.acceptance_votes.detect { |v| v.user_id == current_user.id }
    # Use `new` not `build` so we do not add a blank vote to the association (nil decision
    # was shown as "Reject" in the tally list and could confuse the form).
    @current_acceptance_vote = av || MembershipApplicationAcceptanceVote.new(
      membership_application: @application,
      user: current_user
    )
  end

  def link_user
    user = User.non_service_accounts.find(params[:user_id])
    @application.update!(user: user)
    redirect_to membership_application_path(@application),
                notice: "Application linked to #{user.display_name}."
  end

  def unlink_user
    @application.update!(user: nil)
    redirect_to membership_application_path(@application),
                notice: 'Member link removed from this application.'
  end

  def save_tour_feedback
    if @application.draft?
      redirect_to membership_application_path(@application),
                  alert: 'Tour feedback is available after the application is submitted.'
      return
    end

    feedback = @application.tour_feedbacks.find_or_initialize_by(user: current_user)
    feedback.assign_attributes(tour_feedback_params)
    if feedback.save
      redirect_to membership_application_path(@application),
                  notice: 'Tour feedback saved.'
    else
      redirect_to membership_application_path(@application),
                  alert: feedback.errors.full_messages.to_sentence
    end
  end

  def vote_acceptance
    vote = @application.acceptance_votes.find_or_initialize_by(user: current_user)
    vote.assign_attributes(acceptance_vote_params)
    if vote.save
      redirect_to membership_application_path(@application),
                  notice: 'Your acceptance vote was saved.'
    else
      redirect_to membership_application_path(@application),
                  alert: vote.errors.full_messages.to_sentence
    end
  end

  def approve
    notes = params[:admin_notes]
    result = MembershipApplications::FinalizeApproval.call(
      application: @application,
      admin: current_user,
      notes: notes
    )

    if result.failure?
      redirect_to membership_application_path(@application), alert: result.message
      return
    end

    if result.queued_mail
      redirect_to edit_queued_mail_path(result.queued_mail),
                  notice: 'Application approved. Review and edit the queued welcome email, ' \
                          'then approve it in the mail queue to send.'
    else
      redirect_to membership_application_path(@application),
                  notice: 'Application approved. No welcome email was queued (recipient has no email address).'
    end
  end

  def reject
    notes = params[:admin_notes]
    qm = @application.reject!(current_user, notes: notes)

    if qm
      redirect_to edit_queued_mail_path(qm),
                  notice: 'Application rejected. Review and edit the queued message, ' \
                          'then approve it in the mail queue to send.'
    else
      redirect_to membership_application_path(@application),
                  notice: 'Application rejected. No email was queued (recipient has no email address).'
    end
  end

  def delay_for_review
    notes = params[:admin_notes]
    @application.delay_for_review!(current_user, notes: notes)
    redirect_to membership_application_path(@application),
                notice: 'Application marked as under review.'
  end

  def vote_ai_feedback
    unless @application.ai_feedback_processed?
      redirect_to membership_application_path(@application),
                  alert: 'Admin feedback is only available after AI feedback has been processed.'
      return
    end

    vote = @application.ai_feedback_votes.find_or_initialize_by(user: current_user)
    vote.assign_attributes(ai_feedback_vote_params)
    if vote.save
      redirect_to membership_application_path(@application),
                  notice: 'Your feedback on the AI review was saved.'
    else
      redirect_to membership_application_path(@application),
                  alert: vote.errors.full_messages.to_sentence
    end
  end

  private

  def require_executive_director_for_final_decision!
    return if true_user&.can_finalize_membership_application?

    redirect_to membership_application_path(@application),
                alert: 'Only members trained as Executive Director may approve, reject, or delay applications.'
  end

  def require_submitted_for_delay!
    return if @application.submitted?

    redirect_to membership_application_path(@application),
                alert: 'Only open applications can be marked for delayed review.'
  end

  def require_pending_application_for_acceptance_vote!
    return if @application.acceptance_vote_open?

    redirect_to membership_application_path(@application),
                alert: 'Acceptance votes can only be cast while the application is pending.'
  end

  def tour_feedback_params
    params.expect(tour_feedback: %i[attitude impressions engagement fit_feeling])
  end

  def acceptance_vote_params
    params.expect(acceptance_vote: [:decision])
  end

  def ai_feedback_vote_params
    params.expect(ai_feedback_vote: %i[stance reason])
  end

  def set_application_admin
    rel = MembershipApplication
    if action_name == 'show'
      rel = rel.includes(ai_feedback_votes: :user, tour_feedbacks: :user, acceptance_votes: :user)
    end
    @application = rel.find(params[:id])
  end
end
