class SheetEntry < ApplicationRecord
  include NormalizesEmail

  normalizes_email_field :email

  belongs_to :user, optional: true
  ACCESS_COLUMNS = %i[
    rfid
    laser
    sewing_machine
    serger
    embroidery_machine
    dremel
    ender
    prusa
    laminator
    shaper
    general_shop
    event_host
    vinyl_cutter
    mpcnc_marlin
    longmill
  ].freeze

  validates :name, presence: true

  def rfid=(value)
    super(RfidNormalizer.call(value))
  end

  scope :with_email, -> { where.not(email: nil) }

  def access_permissions
    ACCESS_COLUMNS.filter_map do |column|
      value = self[column]
      next if value.blank?

      column.to_s.humanize
    end
  end
end
