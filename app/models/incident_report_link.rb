class IncidentReportLink < ApplicationRecord
  belongs_to :incident_report

  validates :title, presence: true
  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: 'must be a valid URL' }

  scope :ordered, -> { order(:position, :created_at) }
end
