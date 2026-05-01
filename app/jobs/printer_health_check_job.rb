class PrinterHealthCheckJob < ApplicationJob
  queue_as :default

  def perform
    Printer.ordered.find_each do |printer|
      result = CupsService.printer_health(
        printer.cups_printer_name,
        cups_printer_server: printer.cups_printer_server
      )

      if result.ok
        printer.record_health_success!
      else
        printer.record_health_failure!(result.message)
      end
    end
  end
end
