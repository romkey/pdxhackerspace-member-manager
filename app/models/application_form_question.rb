class ApplicationFormQuestion < ApplicationRecord
  FIELD_TYPES = %w[text textarea radio email].freeze

  belongs_to :application_form_page
  has_many :application_answers, dependent: :destroy

  validates :label, presence: true
  validates :field_type, presence: true, inclusion: { in: FIELD_TYPES }

  scope :ordered, -> { order(:position, :id) }

  def options
    return [] if options_json.blank?

    JSON.parse(options_json)
  rescue JSON::ParserError
    []
  end

  def options=(list)
    self.options_json = Array(list).reject(&:blank?).to_json
  end

  def radio?
    field_type == 'radio'
  end

  def textarea?
    field_type == 'textarea'
  end
end
