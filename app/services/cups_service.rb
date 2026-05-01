require 'open3'

class CupsService
  class PrintError < StandardError; end

  # Returns an array of hashes with CUPS printer info from lpstat.
  # Each hash: { name: "Printer_Name", description: "...", status: "idle" }
  def self.available_printers
    output = run_command('lpstat', '-p', '-d')
    parse_lpstat(output)
  rescue Errno::ENOENT
    Rails.logger.warn('CupsService: lpstat not found — CUPS client tools not installed')
    []
  rescue PrintError => e
    Rails.logger.warn("CupsService: CUPS not available — #{e.message}")
    []
  end

  # Returns true if CUPS is reachable and has at least one printer.
  def self.cups_available?
    available_printers.any?
  rescue StandardError
    false
  end

  # Print a file to a specific CUPS printer.
  # Returns the CUPS job ID on success, raises PrintError on failure.
  def self.print_file(file_path, cups_printer_name, cups_printer_server: nil, options: {})
    args = print_command_args(cups_printer_name, cups_printer_server: cups_printer_server)
    options.each { |key, val| args.push('-o', "#{key}=#{val}") }
    args.push(file_path.to_s)

    output = run_command(*args)
    job_id = output[/request id is (\S+)/, 1]
    raise PrintError, "Unexpected lp output: #{output}" unless job_id

    Rails.logger.info(
      "CupsService: Printed #{file_path} to #{cups_destination(cups_printer_name, cups_printer_server)} (job #{job_id})"
    )
    job_id
  end

  # Print raw data (e.g. PDF bytes from Prawn) by writing to a temp file first.
  def self.print_data(data, cups_printer_name, cups_printer_server: nil, filename: 'print_job.pdf', options: {})
    Tempfile.create(['cups_print_', File.extname(filename)]) do |tmp|
      tmp.binmode
      tmp.write(data)
      tmp.flush
      print_file(tmp.path, cups_printer_name, cups_printer_server: cups_printer_server, options: options)
    end
  end

  # Send a test page to the printer.
  def self.test_print(cups_printer_name, cups_printer_server: nil)
    args = print_command_args(cups_printer_name, cups_printer_server: cups_printer_server)
    args.push('-o', 'raw', '/usr/share/cups/data/testprint')

    output = run_command(*args)
    job_id = output[/request id is (\S+)/, 1]
    raise PrintError, "Test print failed: #{output}" unless job_id

    job_id
  rescue Errno::ENOENT => e
    raise PrintError, "CUPS test page not found: #{e.message}"
  end

  def self.print_command_args(cups_printer_name, cups_printer_server: nil)
    args = ['lp']
    args.push('-h', cups_printer_server) if cups_printer_server.present?
    args.push('-d', cups_printer_name)
    args
  end
  private_class_method :print_command_args

  def self.run_command(*args)
    stdout, stderr, status = Open3.capture3(*args)
    raise PrintError, "Command '#{args.first}' failed (exit #{status.exitstatus}): #{stderr}" unless status.success?

    stdout
  end
  private_class_method :run_command

  def self.cups_destination(cups_printer_name, cups_printer_server)
    return cups_printer_name if cups_printer_server.blank?

    "#{cups_printer_server}/#{cups_printer_name}"
  end
  private_class_method :cups_destination

  def self.parse_lpstat(output)
    printers = []
    current = nil

    output.each_line do |line|
      case line
      when /^printer (\S+) (?:is |now )?(.*)/
        current = { name: Regexp.last_match(1), status: Regexp.last_match(2).strip, description: '' }
        printers << current
      when /^\s+Description:\s+(.*)/
        current[:description] = Regexp.last_match(1).strip if current
      end
    end

    printers
  end
  private_class_method :parse_lpstat
end
