class Printer < ApplicationRecord
  validates :name, presence: true, uniqueness: true
  validates :cups_printer_name, presence: true, uniqueness: true

  scope :ordered, -> { order(:position, :name) }
  scope :default_printer, -> { where(default_printer: true) }

  before_save :ensure_single_default

  def to_s
    name
  end

  def self.default
    default_printer.first || ordered.first
  end

  private

  def ensure_single_default
    return unless default_printer? && default_printer_changed?

    Printer.where.not(id: id).update_all(default_printer: false) # rubocop:disable Rails/SkipsModelValidations
  end
end
