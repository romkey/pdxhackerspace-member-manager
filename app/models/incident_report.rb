class IncidentReport < ApplicationRecord
  INCIDENT_TYPES = [
    ['Code of Conduct', 'code_of_conduct'],
    ['Open Doors', 'open_doors'],
    ['Equipment Issue', 'equipment_issue'],
    ['Trash Issue', 'trash_issue'],
    ['Damage', 'damage'],
    ['Theft', 'theft'],
    ['Other', 'other']
  ].freeze

  STATUSES = [
    ['Draft', 'draft'],
    ['In Progress', 'in_progress'],
    ['Resolved', 'resolved']
  ].freeze

  belongs_to :reporter, class_name: 'User'
  has_and_belongs_to_many :involved_members, 
                          class_name: 'User',
                          join_table: 'incident_report_members'
  has_many_attached :photos
  has_many :links, class_name: 'IncidentReportLink', dependent: :destroy

  accepts_nested_attributes_for :links, allow_destroy: true, reject_if: :all_blank

  validates :incident_date, presence: true
  validates :subject, presence: true
  validates :incident_type, presence: true, inclusion: { in: INCIDENT_TYPES.map(&:last) }
  validates :other_type_explanation, presence: true, if: -> { incident_type == 'other' }
  validates :status, presence: true, inclusion: { in: STATUSES.map(&:last) }

  scope :ordered, -> { order(incident_date: :desc, created_at: :desc) }
  scope :involving_user, ->(user) { joins(:involved_members).where(users: { id: user.id }) }
  scope :by_status, ->(status) { where(status: status) }
  scope :open, -> { where(status: %w[draft in_progress]) }
  scope :resolved, -> { where(status: 'resolved') }

  def incident_type_display
    if incident_type == 'other' && other_type_explanation.present?
      "Other: #{other_type_explanation}"
    else
      INCIDENT_TYPES.find { |t| t[1] == incident_type }&.first || incident_type
    end
  end

  def status_display
    STATUSES.find { |s| s[1] == status }&.first || status
  end

  def draft?
    status == 'draft'
  end

  def in_progress?
    status == 'in_progress'
  end

  def resolved?
    status == 'resolved'
  end

  # Create journal entries for newly involved members
  # Call this from controller after saving with new member associations
  def create_journal_entries_for_members(member_ids, actor: nil)
    User.where(id: member_ids).find_each do |member|
      Journal.record_incident_involvement!(
        user: member,
        incident_report: self,
        actor: actor
      )
    end
  end
end
