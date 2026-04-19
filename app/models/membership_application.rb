class MembershipApplication < ApplicationRecord
  STATUSES = %w[draft submitted under_review approved rejected].freeze

  # Training topic name (TrainingTopic.name) — viewers with this training see applicant PII without masking.
  EXECUTIVE_DIRECTOR_TRAINING_TOPIC_NAME = 'Executive Director'.freeze
  ASSISTANT_EXECUTIVE_DIRECTOR_TRAINING_TOPIC_NAME = 'Assistant Executive Director'.freeze

  # Names must match +TrainingTopic.name+ exactly. Used to notify staff when an application is submitted.
  STAFF_APPLICATION_ALERT_TRAINING_TOPIC_NAMES = [
    EXECUTIVE_DIRECTOR_TRAINING_TOPIC_NAME,
    ASSISTANT_EXECUTIVE_DIRECTOR_TRAINING_TOPIC_NAME
  ].freeze

  # Form question labels whose answers are masked (with reveal control) for viewers without the training above.
  FORM_ANSWER_LABELS_CONTACT_SENSITIVE = [
    'Mailing Address',
    'Phone number',
    'Member Email',
    'Member Phone'
  ].freeze

  belongs_to :reviewed_by, class_name: 'User', optional: true
  belongs_to :user, optional: true
  has_many :application_answers, dependent: :destroy
  has_many :ai_feedback_votes, -> { order(created_at: :asc) },
           class_name: 'MembershipApplicationAiFeedbackVote', dependent: :destroy
  has_many :tour_feedbacks, -> { includes(:user).order(updated_at: :desc) },
           class_name: 'MembershipApplicationTourFeedback', dependent: :destroy
  has_many :acceptance_votes, class_name: 'MembershipApplicationAcceptanceVote', dependent: :destroy

  validates :email, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :token, presence: true, uniqueness: true

  before_validation :generate_token, on: :create

  scope :drafts, -> { where(status: 'draft') }
  scope :ai_feedback_unprocessed, lambda {
    where.not(status: 'draft').where(ai_feedback_processed_at: nil)
  }
  scope :submitted_apps, -> { where(status: 'submitted') }
  scope :under_review_apps, -> { where(status: 'under_review') }
  scope :approved, -> { where(status: 'approved') }
  scope :rejected, -> { where(status: 'rejected') }
  # Applications awaiting a final decision (Open or Under Review).
  scope :pending, -> { where(status: %w[submitted under_review]) }
  scope :newest_first, -> { order(created_at: :desc) }
  scope :admin_search, lambda { |query|
    raw = query.to_s.strip
    if raw.blank?
      all
    else
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(raw.downcase)}%"
      where(
        <<~SQL.squish,
          LOWER(membership_applications.email) LIKE :p
          OR EXISTS (
            SELECT 1 FROM application_answers aa
            WHERE aa.membership_application_id = membership_applications.id
            AND LOWER(aa.value) LIKE :p
          )
          OR EXISTS (
            SELECT 1 FROM users u
            WHERE u.id = membership_applications.user_id
            AND (
              LOWER(COALESCE(u.full_name, '')) LIKE :p
              OR LOWER(COALESCE(u.email, '')) LIKE :p
              OR LOWER(COALESCE(u.username, '')) LIKE :p
            )
          )
        SQL
        p: pattern
      )
    end
  }

  def draft?
    status == 'draft'
  end

  def submitted?
    status == 'submitted'
  end

  def under_review?
    status == 'under_review'
  end

  def approved?
    status == 'approved'
  end

  def rejected?
    status == 'rejected'
  end

  def submit!
    update!(status: 'submitted', submitted_at: Time.current)
    Journal.record_application_event!(application: self, action: 'application_submitted')
    MembershipApplicationAiFeedbackJob.perform_later(id)
    MembershipApplications::NotifyDirectorsOfSubmission.call(self)
  end

  # Updates status and journal only. The web UI uses +MembershipApplications::FinalizeApproval+ instead
  # (creates or links a +User+, queues +application_approved+ mail).
  def approve!(admin, notes: nil)
    update!(
      status: 'approved',
      reviewed_by: admin,
      reviewed_at: Time.current,
      admin_notes: notes
    )
    Journal.record_application_event!(application: self, action: 'application_approved', actor: admin)
  end

  # Marks the application rejected, journals, and queues the applicant rejection email (pending mail queue).
  # Returns the new +QueuedMail+ or +nil+ if no message was queued (e.g. no destination email).
  def reject!(admin, notes: nil)
    queued_mail = nil
    MembershipApplication.transaction do
      update!(
        status: 'rejected',
        reviewed_by: admin,
        reviewed_at: Time.current,
        admin_notes: notes
      )
      Journal.record_application_event!(application: self, action: 'application_rejected', actor: admin)
      queued_mail = QueuedMail.enqueue_application_rejected(self, reason: notes.presence)
    end
    queued_mail
  end

  # Marks the application as delayed for executive review (no applicant email).
  def delay_for_review!(admin, notes: nil)
    raise ArgumentError, 'Only open applications can be delayed for review' unless submitted?

    update!(
      status: 'under_review',
      reviewed_by: admin,
      reviewed_at: Time.current,
      admin_notes: notes
    )
    Journal.record_application_event!(application: self, action: 'application_delayed_for_review', actor: admin)
  end

  def status_display
    return 'Open' if submitted?

    return 'Under Review' if under_review?

    status&.titleize
  end

  def status_badge_color
    case status
    when 'submitted' then 'primary'
    when 'under_review' then 'warning'
    when 'approved' then 'success'
    when 'rejected' then 'danger'
    else 'secondary'
    end
  end

  def answer_for(question)
    application_answers.find_by(application_form_question: question)
  end

  # Display name for admin lists: "Name" on the first form page, then linked member, else em dash.
  def applicant_display_name(name_question_id: nil)
    qid = name_question_id
    if qid.nil?
      name_q_scope = ApplicationFormQuestion.joins(:application_form_page)
      qid = name_q_scope.where(application_form_pages: { position: 1 }, label: 'Name').pick(:id)
    end
    if qid
      ans = application_answers.detect { |a| a.application_form_question_id == qid }
      name = ans&.value&.strip
      return name if name.present?
    end
    user&.display_name.presence || '—'
  end

  # Returns answers grouped by page for display
  def answers_by_page
    ApplicationFormPage.ordered.includes(:questions).map do |page|
      questions_with_answers = page.questions.ordered.map do |q|
        { question: q, answer: answer_for(q) }
      end
      { page: page, questions: questions_with_answers }
    end
  end

  # Plain-text bundle of the application for LLM prompts (email + Q&A by page).
  def application_text_for_ai
    lines = ["Email: #{email}"]
    answers_by_page.each do |entry|
      lines << "\n## #{entry[:page].title}"
      entry[:questions].each do |h|
        q = h[:question]
        a = h[:answer]
        lines << "Q: #{q.label}"
        lines << "A: #{a&.value.presence || '(no answer)'}"
      end
    end
    lines.join("\n")
  end

  def ai_feedback_processed?
    ai_feedback_processed_at.present?
  end

  def ai_feedback_admin_vote_counts
    # Default association order(:created_at) breaks GROUP BY under PostgreSQL.
    ai_feedback_votes.unscope(:order).group(:stance).count
  end

  def acceptance_vote_counts
    acceptance_votes.group(:decision).count
  end

  def acceptance_vote_open?
    !approved? && !rejected?
  end

  AI_FEEDBACK_REC_BADGES = {
    'accept' => 'success', 'accepted' => 'success', 'approve' => 'success', 'approved' => 'success',
    'reject' => 'danger', 'rejected' => 'danger', 'deny' => 'danger', 'denied' => 'danger',
    'needs_review' => 'warning', 'need_more_info' => 'warning', 'clarify' => 'warning', 'uncertain' => 'warning'
  }.freeze

  # Bootstrap badge color for +ai_feedback_recommendation+ (free-form model output).
  def ai_feedback_recommendation_badge_color
    key = ai_feedback_recommendation.to_s.downcase.strip.tr(' ', '_')
    AI_FEEDBACK_REC_BADGES.fetch(key, 'secondary')
  end

  private

  def generate_token
    self.token ||= SecureRandom.alphanumeric(32)
  end
end
