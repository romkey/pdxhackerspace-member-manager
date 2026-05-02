require 'test_helper'

class RfidNormalizerTest < ActiveSupport::TestCase
  test 'returns nil for nil or blank' do
    assert_nil RfidNormalizer.call(nil)
    assert_nil RfidNormalizer.call('')
    assert_nil RfidNormalizer.call("  \t\n")
  end

  test 'removes all whitespace including after comma without adding spaces' do
    assert_equal '123,4567', RfidNormalizer.call('123,4567')
    assert_equal '123,4567', RfidNormalizer.call('123, 4567')
    assert_equal '123,4567', RfidNormalizer.call('123 ,4567')
    assert_equal '123,4567', RfidNormalizer.call("123 ,\t 4567")
    assert_equal 'AB,CD', RfidNormalizer.call('AB , CD')
  end

  test 'strips leading zeros from numeric suffix after comma' do
    assert_equal '123,456', RfidNormalizer.call('123,0456')
    assert_equal '123,456', RfidNormalizer.call('123, 00456')
    assert_equal 'fac,7', RfidNormalizer.call('fac,007')
    assert_equal '1,0', RfidNormalizer.call('1,000')
  end

  test 'does not alter non-numeric suffix after comma' do
    assert_equal '12,0AB', RfidNormalizer.call('12,0AB')
    assert_equal '12,00AB', RfidNormalizer.call('12,00AB')
  end

  test 'leaves values without comma unchanged aside from whitespace removal' do
    assert_equal 'RFID001', RfidNormalizer.call(' RFID001 ')
    assert_equal 'deadbeef', RfidNormalizer.call('dead beef')
  end

  test 'idempotent' do
    once = RfidNormalizer.call('123, 0456')
    assert_equal once, RfidNormalizer.call(once)
  end
end
