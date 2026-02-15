namespace :access_logs do
  desc 'Import access logs from log files in a directory'
  task import: :environment do
    directory = ENV.fetch('ACCESS_LOGS_DIRECTORY', nil)

    if directory.blank?
      puts 'ERROR: ACCESS_LOGS_DIRECTORY environment variable is required'
      puts 'Usage: ACCESS_LOGS_DIRECTORY=/path/to/logs rails access_logs:import'
      exit 1
    end

    unless Dir.exist?(directory)
      puts "ERROR: Directory does not exist: #{directory}"
      exit 1
    end

    puts "Importing access logs from: #{directory}"

    # Pattern to match yyyy-mm-dd.log filenames
    log_file_pattern = /\A(\d{4}-\d{2}-\d{2})\.log\z/

    imported_count = 0
    skipped_count = 0
    duplicate_count = 0
    error_count = 0

    Dir.glob(File.join(directory, '*.log')).each do |file_path|
      filename = File.basename(file_path)

      # Extract year from filename if needed
      match = filename.match(log_file_pattern)
      unless match
        puts "Skipping file with unexpected name format: #{filename}"
        skipped_count += 1
        next
      end

      file_year = match[1].split('-').first.to_i

      File.readlines(file_path).each_with_index do |line, line_num|
        line = line.chomp
        next if line.blank?

        # Skip system messages that shouldn't be stored
        next if should_skip_line?(line)

        begin
          original_line = line
          parsed = parse_log_line(line, file_year, original_line)

          if parsed
            # Try to find matching user by name
            user = find_user_by_name(parsed[:name]) if parsed[:name].present?

            if AccessLog.exists?(raw_text: parsed[:raw_text], logged_at: parsed[:logged_at])
              duplicate_count += 1
              next
            end

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
            if AccessLog.exists?(raw_text: original_line, logged_at: nil)
              duplicate_count += 1
              next
            end

            AccessLog.create!(
              raw_text: original_line,
              logged_at: nil
            )
          end
          imported_count += 1
        rescue StandardError => e
          puts "Error processing line #{line_num + 1} in #{filename}: #{e.message}"
          error_count += 1
        end
      end
    end

    puts "\nImport complete:"
    puts "  Imported: #{imported_count}"
    puts "  Skipped files: #{skipped_count}"
    puts "  Duplicates: #{duplicate_count}"
    puts "  Errors: #{error_count}"
  end
end

def should_skip_line?(line)
  # Remove filename prefix if present for pattern matching
  check_line = line.sub(/\A\d{4}-\d{2}-\d{2}\.log:/, '')

  # Skip patterns for system messages
  skip_patterns = [
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
  ]

  skip_patterns.any? { |pattern| check_line.match?(pattern) }
end

def parse_log_line(line, file_year, original_line = nil)
  original_line ||= line
  # Remove filename prefix if present (e.g., "2025-09-08.log:") for parsing
  parse_line = line.sub(/\A\d{4}-\d{2}-\d{2}\.log:/, '')

  # Pattern 1: Standard access control format
  # "Nov 15 14:41:35 unit2 accesscontrol[2113]: Valeriy Novytskyy has opened unit2 front door"
  # "2025-11-18T05:54:25-08:00 unit2 accesscontrol[2150]:  Sean Brown has opened unit2 front door"
  pattern1 = /\A(?:(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2})|(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}))\s+(\S+)\s+accesscontrol(?:\[\d+\])?:\s+(.+?)\s+has\s+(opened|locked|unlocked)\s+(.+)\z/

  match = parse_line.match(pattern1)
  if match
    timestamp_str = match[1] || match[2]
    match[3]
    name = match[4].strip
    action = match[5]
    location = match[6].strip

    logged_at = parse_timestamp(timestamp_str, file_year)

    return {
      logged_at: logged_at,
      name: name,
      action: action,
      location: location,
      raw_text: original_line
    }
  end

  # Pattern 2: Laser access format
  # "Sep  8 21:20:14 laser-access accesscontrol: John Bates disabled laser-access"
  # "Sep 10 14:09:38 laser-access accesscontrol: Paul Maupoux enabled laser-access"
  # "Aug 30 19:58:37 laser-access accesscontrol: Jon H. enabled unit1 laser"
  pattern2 = /\A(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+laser-access\s+accesscontrol:\s+(.+?)\s+(enabled|disabled)\s+(?:laser-access|unit\d+\s+laser)\z/

  match = parse_line.match(pattern2)
  if match
    timestamp_str = match[1]
    name = match[2].strip
    action = match[3]

    logged_at = parse_timestamp(timestamp_str, file_year)

    return {
      logged_at: logged_at,
      name: name,
      action: action,
      location: 'laser-access',
      raw_text: original_line
    }
  end

  # Pattern 3: "location action by name" format
  # "2025-10-25T17:26:03-07:00 unit2 accesscontrol[2214]: unit2 front door unlocked by Kenny McElroy"
  # "2025-10-25T17:05:39-07:00 unit2 accesscontrol[2214]: unit2 front door locked by Jon Hannis"
  pattern3 = /\A(?:(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2})|(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}))\s+(\S+)\s+accesscontrol(?:\[\d+\])?:\s+(.+?)\s+(locked|unlocked)\s+by\s+(.+)\z/

  match = parse_line.match(pattern3)
  if match
    timestamp_str = match[1] || match[2]
    match[3]
    location = match[4].strip
    action = match[5]
    name = match[6].strip

    logged_at = parse_timestamp(timestamp_str, file_year)

    return {
      logged_at: logged_at,
      name: name,
      action: action,
      location: location,
      raw_text: original_line
    }
  end

  # Pattern 4: "name found location is already action" format
  # "2025-11-01T16:38:02-07:00 unit2 accesscontrol[2214]: Tom Hansen found unit2 front door is already unlocked"
  pattern4 = /\A(?:(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2})|(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}))\s+(\S+)\s+accesscontrol(?:\[\d+\])?:\s+(.+?)\s+found\s+(.+?)\s+is\s+already\s+(locked|unlocked)\z/

  match = parse_line.match(pattern4)
  if match
    timestamp_str = match[1] || match[2]
    match[3]
    name = match[4].strip
    location = match[5].strip
    action = match[6]

    logged_at = parse_timestamp(timestamp_str, file_year)

    return {
      logged_at: logged_at,
      name: name,
      action: action,
      location: location,
      raw_text: original_line
    }
  end

  # No match
  nil
end

def parse_timestamp(timestamp_str, file_year)
  # Try ISO 8601 format first: "2025-11-18T05:54:25-08:00"
  return Time.zone.parse(timestamp_str) if timestamp_str.match?(/\A\d{4}-\d{2}-\d{2}T/)

  # Try syslog format: "Nov 15 14:41:35" or "Sep  8 21:20:14"
  # Parse month name, day, and time, then add year from file
  if timestamp_str.match?(/\A\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}\z/)
    # Parse the timestamp and add the year
    parsed = Time.strptime("#{timestamp_str} #{file_year}", '%b %d %H:%M:%S %Y')
    return Time.zone.local(parsed.year, parsed.month, parsed.day, parsed.hour, parsed.min, parsed.sec)
  end

  # Fallback: try to parse as-is
  Time.zone.parse(timestamp_str)
rescue StandardError => e
  puts "Warning: Could not parse timestamp '#{timestamp_str}': #{e.message}"
  nil
end

def find_user_by_name(name)
  return nil if name.blank?

  normalized_name = name.strip

  # Check if name has an abbreviated last name (e.g., "Jon H.")
  if normalized_name.match?(/\A\w+\s+\w\.\z/i)
    # Try to match with abbreviated last name
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
  # Parse "Jon H." or "Melinda H." into first name and last initial
  # Handle potential extra spaces
  match = abbreviated_name.strip.match(/\A(\w+)\s+(\w)\.\z/i)
  return nil unless match

  first_name = match[1].strip
  last_initial = match[2].upcase

  # Find users where first name matches and last name starts with the initial
  # Handle names that might have multiple spaces or parts
  # Use TRIM to handle extra spaces and get the last word as the last name
  matching_users = User.where(
    "LOWER(TRIM(SPLIT_PART(full_name, ' ', 1))) = ? AND UPPER(SUBSTRING(TRIM(SPLIT_PART(full_name, ' ', -1)) FROM 1 FOR 1)) = ?",
    first_name.downcase,
    last_initial
  ).to_a

  # If more than one match, skip it (return nil)
  return nil if matching_users.length != 1

  matching_users.first
end
