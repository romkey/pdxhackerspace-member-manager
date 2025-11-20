class SheetEntry < ApplicationRecord
  belongs_to :user, optional: true
  has_many :paypal_payments, dependent: :nullify
  has_many :recharge_payments, dependent: :nullify
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

  scope :with_email, -> { where.not(email: nil) }

  before_validation :normalize_email

  def access_permissions
    ACCESS_COLUMNS.filter_map do |column|
      value = self[column]
      next if value.blank?

      column.to_s.humanize
    end
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase.presence
  end
end
