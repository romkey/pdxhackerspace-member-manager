class Printer < ApplicationRecord
  before_validation :normalize_cups_printer_server

  validates :name, presence: true, uniqueness: true
  validates :cups_printer_name, presence: true, uniqueness: { scope: :cups_printer_server }

  scope :ordered, -> { order(:position, :name) }
  scope :default_printer, -> { where(default_printer: true) }

  before_save :ensure_single_default

  def to_s
    name
  end

  def self.default
    default_printer.first || ordered.first
  end

  def cups_destination
    return cups_printer_name if cups_printer_server.blank?

    "#{cups_printer_server}/#{cups_printer_name}"
  end

  private

  def normalize_cups_printer_server
    self.cups_printer_server = cups_printer_server.to_s.strip
  end

  def ensure_single_default
    return unless default_printer? && default_printer_changed?

    Printer.where.not(id: id).update_all(default_printer: false)
  end
end
