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

  belongs_to :reporter, class_name: 'User'
  has_and_belongs_to_many :involved_members, 
                          class_name: 'User',
                          join_table: 'incident_report_members'
  has_many_attached :photos

  validates :incident_date, presence: true
  validates :subject, presence: true
  validates :incident_type, presence: true, inclusion: { in: INCIDENT_TYPES.map(&:last) }
  validates :other_type_explanation, presence: true, if: -> { incident_type == 'other' }

  scope :ordered, -> { order(incident_date: :desc, created_at: :desc) }
  scope :involving_user, ->(user) { joins(:involved_members).where(users: { id: user.id }) }

  def incident_type_display
    if incident_type == 'other' && other_type_explanation.present?
      "Other: #{other_type_explanation}"
    else
      INCIDENT_TYPES.find { |t| t[1] == incident_type }&.first || incident_type
    end
  end
end
