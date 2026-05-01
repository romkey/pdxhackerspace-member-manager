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
end
