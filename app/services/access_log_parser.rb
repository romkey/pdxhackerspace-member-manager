# Service for parsing access log lines
# Used by both the import rake task and the access webhook
class AccessLogParser
  SKIP_PATTERNS = [
    /\breloading access list\z/i,
    /\bA card was presented at .+ and access was denied\z/i,
    /\btime check\z/i,
    /\bcomms check\z/i,
    /\A.*:\s*Initializing\z/i,
    /\bis alive\?\z/i,
    /\bis fail\?\??\z/i,
    /\bstarting up!\z/i,
    /\baccess control is online\z/i,
    /\blog check\z/i
  ].freeze

  def initialize(line, file_year: nil)
    @original_line = line.to_s.chomp
    @file_year = file_year || Time.current.year
  end

  def should_skip?
    return true if @original_line.blank?

    # Remove filename prefix if present for pattern matching
    check_line = @original_line.sub(/\A\d{4}-\d{2}-\d{2}\.log:/, '')

    SKIP_PATTERNS.any? { |pattern| check_line.match?(pattern) }
  end

  def parse
    return nil if should_skip?

    # Remove filename prefix if present (e.g., "2025-09-08.log:") for parsing
    parse_line = @original_line.sub(/\A\d{4}-\d{2}-\d{2}\.log:/, '')

    # Try each pattern in order
    parse_pattern1(parse_line) ||
      parse_pattern2(parse_line) ||
      parse_pattern3(parse_line) ||
      parse_pattern4(parse_line)
  end

  def create_access_log!
    parsed = parse

    if parsed
      user = find_user_by_name(parsed[:name]) if parsed[:name].present?

      AccessLog.create!(
        user: user,
        name: parsed[:name],
        location: parsed[:location],
        action: parsed[:action],
        raw_text: parsed[:raw_text],
        logged_at: parsed[:logged_at]
      )
    else
      # Store unmatched lines in raw_text only
      AccessLog.create!(
        raw_text: @original_line,
        logged_at: nil
      )
    end
  end

  private

  # Pattern 1: Standard access control format
  # "Nov 15 14:41:35 unit2 accesscontrol[2113]: Valeriy Novytskyy has opened unit2 front door"
  # "2025-11-18T05:54:25-08:00 unit2 accesscontrol[2150]:  Sean Brown has opened unit2 front door"
  def parse_pattern1(line)
    pattern = /\A(?:(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2})|(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}))\s+(\S+)\s+accesscontrol(?:\[\d+\])?:\s+(.+?)\s+has\s+(opened|locked|unlocked)\s+(.+)\z/

    match = line.match(pattern)
    return nil unless match

    timestamp_str = match[1] || match[2]
    name = match[4].strip
    action = match[5]
    location = match[6].strip

    {
      logged_at: parse_timestamp(timestamp_str),
      name: name,
      action: action,
      location: location,
      raw_text: @original_line
    }
  end

  # Pattern 2: Laser access format
  # "Sep  8 21:20:14 laser-access accesscontrol: John Bates disabled laser-access"
  # "Sep 10 14:09:38 laser-access accesscontrol: Paul Maupoux enabled laser-access"
  def parse_pattern2(line)
    pattern = /\A(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+laser-access\s+accesscontrol:\s+(.+?)\s+(enabled|disabled)\s+(?:laser-access|unit\d+\s+laser)\z/

    match = line.match(pattern)
    return nil unless match

    timestamp_str = match[1]
    name = match[2].strip
    action = match[3]

    {
      logged_at: parse_timestamp(timestamp_str),
      name: name,
      action: action,
      location: 'laser-access',
      raw_text: @original_line
    }
  end

  # Pattern 3: "location action by name" format
  # "2025-10-25T17:26:03-07:00 unit2 accesscontrol[2214]: unit2 front door unlocked by Kenny McElroy"
  def parse_pattern3(line)
    pattern = /\A(?:(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2})|(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}))\s+(\S+)\s+accesscontrol(?:\[\d+\])?:\s+(.+?)\s+(locked|unlocked)\s+by\s+(.+)\z/

    match = line.match(pattern)
    return nil unless match

    timestamp_str = match[1] || match[2]
    location = match[4].strip
    action = match[5]
    name = match[6].strip

    {
      logged_at: parse_timestamp(timestamp_str),
      name: name,
      action: action,
      location: location,
      raw_text: @original_line
    }
  end

  # Pattern 4: "name found location is already action" format
  # "2025-11-01T16:38:02-07:00 unit2 accesscontrol[2214]: Tom Hansen found unit2 front door is already unlocked"
  def parse_pattern4(line)
    pattern = /\A(?:(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2})|(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}))\s+(\S+)\s+accesscontrol(?:\[\d+\])?:\s+(.+?)\s+found\s+(.+?)\s+is\s+already\s+(locked|unlocked)\z/

    match = line.match(pattern)
    return nil unless match

    timestamp_str = match[1] || match[2]
    name = match[4].strip
    location = match[5].strip
    action = match[6]

    {
      logged_at: parse_timestamp(timestamp_str),
      name: name,
      action: action,
      location: location,
      raw_text: @original_line
    }
  end

  def parse_timestamp(timestamp_str)
    # Try ISO 8601 format first: "2025-11-18T05:54:25-08:00"
    return Time.zone.parse(timestamp_str) if timestamp_str.match?(/\A\d{4}-\d{2}-\d{2}T/)

    # Try syslog format: "Nov 15 14:41:35" or "Sep  8 21:20:14"
    if timestamp_str.match?(/\A\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}\z/)
      parsed = Time.strptime("#{timestamp_str} #{@file_year}", '%b %d %H:%M:%S %Y')
      return Time.zone.local(parsed.year, parsed.month, parsed.day, parsed.hour, parsed.min, parsed.sec)
    end

    # Fallback: try to parse as-is
    Time.zone.parse(timestamp_str)
  rescue StandardError => e
    Rails.logger.warn("AccessLogParser: Could not parse timestamp '#{timestamp_str}': #{e.message}")
    nil
  end

  def find_user_by_name(name)
    return nil if name.blank?

    normalized_name = name.strip

    # Check if name has an abbreviated last name (e.g., "Jon H.")
    if normalized_name.match?(/\A\w+\s+\w\.\z/i)
      return find_user_by_abbreviated_name(normalized_name)
    end

    # Match by full_name or aliases
    user = User.by_name_or_alias(normalized_name).first
    return nil unless user

    # Auto-add differing name as alias
    user.add_alias!(normalized_name) if user.full_name.present? && user.full_name.strip.downcase != normalized_name.downcase

    user
  end

  def find_user_by_abbreviated_name(abbreviated_name)
    match = abbreviated_name.strip.match(/\A(\w+)\s+(\w)\.\z/i)
    return nil unless match

    first_name = match[1].strip
    last_initial = match[2].upcase

    matching_users = User.where(
      "LOWER(TRIM(SPLIT_PART(full_name, ' ', 1))) = ? AND UPPER(SUBSTRING(TRIM(SPLIT_PART(full_name, ' ', -1)) FROM 1 FOR 1)) = ?",
      first_name.downcase,
      last_initial
    ).to_a

    # If more than one match, skip it (return nil)
    return nil if matching_users.length != 1

    matching_users.first
  end
end
