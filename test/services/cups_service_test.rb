require 'test_helper'

class CupsServiceTest < ActiveSupport::TestCase
  test 'print command args include the configured server and printer' do
    args = CupsService.send(
      :print_command_args,
      'Office_Printer',
      cups_printer_server: 'print.example.org'
    )

    assert_equal ['lp', '-h', 'print.example.org', '-d', 'Office_Printer'], args
  end

  test 'print command args use the default CUPS server when no server is configured' do
    args = CupsService.send(:print_command_args, 'Local_Printer')

    assert_equal ['lp', '-d', 'Local_Printer'], args
  end

  test 'print command args ignore blank server values' do
    args = CupsService.send(:print_command_args, 'Local_Printer', cups_printer_server: '')

    assert_equal ['lp', '-d', 'Local_Printer'], args
  end

  test 'printer status args include the configured server and printer' do
    args = CupsService.send(
      :printer_status_args,
      'Office_Printer',
      cups_printer_server: 'print.example.org'
    )

    assert_equal ['lpstat', '-h', 'print.example.org', '-p', 'Office_Printer'], args
  end

  test 'printer accepting args include the configured server and printer' do
    args = CupsService.send(
      :printer_accepting_args,
      'Office_Printer',
      cups_printer_server: 'print.example.org'
    )

    assert_equal ['lpstat', '-h', 'print.example.org', '-a', 'Office_Printer'], args
  end

  test 'health output is healthy when printer is reachable and accepting jobs' do
    result = CupsService.send(:health_from_lpstat_output, <<~OUTPUT)
      printer Office_Printer is idle. enabled since Fri May 01 06:00:00 2026
      Office_Printer accepting requests since Fri May 01 06:00:00 2026
    OUTPUT

    assert_predicate result, :ok
    assert_equal 'Printer is reachable and accepting jobs', result.message
  end

  test 'health output is unhealthy when printer is not accepting jobs' do
    result = CupsService.send(:health_from_lpstat_output, <<~OUTPUT)
      printer Office_Printer disabled since Fri May 01 06:00:00 2026
      Office_Printer not accepting requests since Fri May 01 06:00:00 2026
    OUTPUT

    assert_not result.ok
    assert_match(/not accepting/i, result.message)
  end
end
