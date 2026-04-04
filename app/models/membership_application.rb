class MembershipApplication < ApplicationRecord
  STATUSES = %w[draft submitted under_review approved rejected].freeze

  belongs_to :reviewed_by, class_name: 'User', optional: true
  belongs_to :user, optional: true
  has_many :application_answers, dependent: :destroy

  validates :email, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :token, presence: true, uniqueness: true

  before_validation :generate_token, on: :create

  scope :drafts, -> { where(status: 'draft') }
  scope :ai_feedback_unprocessed, lambda {
    where.not(status: 'draft').where(ai_feedback_processed_at: nil)
  }
  scope :submitted_apps, -> { where(status: 'submitted') }
  scope :under_review, -> { where(status: 'under_review') }
  scope :approved, -> { where(status: 'approved') }
  scope :rejected, -> { where(status: 'rejected') }
  scope :pending, -> { where(status: %w[submitted under_review]) }
  scope :newest_first, -> { order(created_at: :desc) }

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
  end

  def mark_under_review!(admin)
    update!(status: 'under_review', reviewed_by: admin)
  end

  def approve!(admin, notes: nil)
    update!(
      status: 'approved',
      reviewed_by: admin,
      reviewed_at: Time.current,
      admin_notes: notes
    )
    Journal.record_application_event!(application: self, action: 'application_approved', actor: admin)
  end

  def reject!(admin, notes: nil)
    update!(
      status: 'rejected',
      reviewed_by: admin,
      reviewed_at: Time.current,
      admin_notes: notes
    )
    Journal.record_application_event!(application: self, action: 'application_rejected', actor: admin)
  end

  def status_display
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
