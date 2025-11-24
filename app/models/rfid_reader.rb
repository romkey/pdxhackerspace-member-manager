class RfidReader < ApplicationRecord
  validates :name, presence: true
  validates :key, presence: true, uniqueness: true, length: { is: 32 }

  before_validation :generate_key, on: :create

  def generate_key!
    self.key = generate_unique_key
    save!
  end

  private

  def generate_key
    self.key ||= generate_unique_key
  end

  def generate_unique_key
    loop do
      # Generate exactly 32 characters using alphanumerics and dashes
      # Format: 6 groups of 5 chars separated by dashes = 6*5 + 5 = 35 chars (too long)
      # Format: 4 groups of 7 chars separated by dashes = 4*7 + 3 = 31 chars (too short)
      # Format: 5 groups of 5 chars + 2 dashes = 5*5 + 2 = 27 chars (too short)
      # Format: 6 groups of 4 chars + 5 dashes = 6*4 + 5 = 29 chars (too short)
      # Format: 7 groups of 4 chars + 6 dashes = 7*4 + 6 = 34 chars (too long)
      # Let's use: 5 groups of 5 chars + 4 dashes = 5*5 + 4 = 29 chars (still short)
      # Better: Generate 32 chars with some dashes mixed in
      chars = ('a'..'z').to_a + ('0'..'9').to_a + ['-']
      key = 32.times.map { chars.sample }.join
      # Ensure at least one dash and one alphanumeric
      next if key.count('-') == 0 || key.gsub('-', '').empty?
      break key unless self.class.exists?(key: key)
    end
  end
end
