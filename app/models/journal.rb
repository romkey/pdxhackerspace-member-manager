class Journal < ApplicationRecord
  belongs_to :user
  belongs_to :actor_user, class_name: 'User', optional: true

  validates :action, presence: true
  validates :changes_json, presence: true
  validates :changed_at, presence: true

  scope :highlighted, -> { where(highlight: true) }
  scope :recent, -> { order(changed_at: :desc) }

  # Actions that should always be highlighted
  HIGHLIGHTED_ACTIONS = %w[
    created
    incident_report_involvement
    membership_status_changed
    activated
    deactivated
    banned
  ].freeze

  # Fields whose changes should trigger a highlight
  HIGHLIGHTED_FIELDS = %w[
    membership_status
    active
    banned
    deceased
  ].freeze

  before_save :determine_highlight

  # Create a journal entry for incident report involvement
  def self.record_incident_involvement!(user:, incident_report:, actor: nil)
    create!(
      user: user,
      actor_user: actor,
      action: 'incident_report_involvement',
      changes_json: {
        'incident_report' => {
          'id' => incident_report.id,
          'subject' => incident_report.subject,
          'type' => incident_report.incident_type_display,
          'date' => incident_report.incident_date.to_s
        }
      },
      changed_at: Time.current,
      highlight: true
    )
  end

  private

  def determine_highlight
    # Skip if already explicitly set to true
    return if highlight?

    self.highlight = should_highlight?
  end

  def should_highlight?
    # Check if action is in highlighted list
    return true if HIGHLIGHTED_ACTIONS.include?(action)

    # Check if any highlighted fields were changed
    return true if changes_include_highlighted_fields?

    false
  end

  def changes_include_highlighted_fields?
    return false if changes_json.blank?

    (changes_json.keys & HIGHLIGHTED_FIELDS).any?
  end
end
