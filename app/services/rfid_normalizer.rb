# SPDX-FileCopyrightText: 2025 John Romkey
#
# SPDX-License-Identifier: CC0-1.0

# Canonical form for stored RFID strings: no whitespace; if there is a comma,
# the suffix is stripped of leading zeros when it is purely decimal digits.
class RfidNormalizer
  def self.call(raw)
    new(raw).call
  end

  def initialize(raw)
    @raw = raw
  end

  def call
    return nil if @raw.nil?

    s = @raw.to_s.gsub(/\s+/, '')
    return nil if s.blank?

    comma_at = s.index(',')
    if comma_at
      left = s[0...comma_at]
      right = s[(comma_at + 1)..] || ''
      "#{left},#{normalize_numeric_suffix(right)}"
    else
      s
    end
  end

  private

  def normalize_numeric_suffix(segment)
    return segment if segment.blank?
    return segment unless segment.match?(/\A0*\d+\z/)

    segment.to_i.to_s
  end
end
