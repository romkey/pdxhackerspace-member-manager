require 'test_helper'

class MemberSourceTest < ActiveSupport::TestCase
  test 'enabled? returns true for an enabled source' do
    assert MemberSource.enabled?('authentik')
  end

  test 'enabled? returns false for a disabled source' do
    member_sources(:authentik).update!(enabled: false)

    assert_not MemberSource.enabled?('authentik')
  end

  test 'enabled? returns true for a nonexistent key' do
    assert MemberSource.enabled?('nonexistent')
  end

  test 'enabled? reflects toggle' do
    source = member_sources(:sheet)
    assert MemberSource.enabled?('sheet')

    source.update!(enabled: false)
    assert_not MemberSource.enabled?('sheet')

    source.update!(enabled: true)
    assert MemberSource.enabled?('sheet')
  end

  test 'validates key uniqueness' do
    duplicate = MemberSource.new(key: 'authentik', name: 'Dupe')

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:key], 'has already been taken'
  end

  test 'validates key inclusion' do
    bad = MemberSource.new(key: 'invalid_key', name: 'Bad')

    assert_not bad.valid?
    assert_includes bad.errors[:key], 'is not included in the list'
  end

  test 'enabled scope returns only enabled sources' do
    member_sources(:slack).update!(enabled: false)

    enabled_keys = MemberSource.enabled.pluck(:key)
    assert_includes enabled_keys, 'authentik'
    assert_not_includes enabled_keys, 'slack'
  end

  test 'record_sync! clears error state and marks healthy' do
    source = member_sources(:authentik)
    source.update!(
      sync_status: 'failing',
      consecutive_error_count: 3,
      last_error_message: 'previous failure'
    )

    source.record_sync!

    source.reload
    assert_equal 'healthy', source.sync_status
    assert_equal 0, source.consecutive_error_count
    assert_nil source.last_error_message
    assert source.last_successful_sync_at.present?
  end

  test 'record_failed_sync! increments errors and sets degraded then failing' do
    source = member_sources(:sheet)
    source.update!(sync_status: 'healthy', consecutive_error_count: 0, last_error_message: nil)

    source.record_failed_sync!('first')
    source.reload
    assert_equal 'degraded', source.sync_status
    assert_equal 1, source.consecutive_error_count

    source.record_failed_sync!('second')
    source.reload
    assert_equal 'degraded', source.sync_status
    assert_equal 2, source.consecutive_error_count

    source.record_failed_sync!('third')
    source.reload
    assert_equal 'failing', source.sync_status
    assert_equal 3, source.consecutive_error_count
    assert_match(/third/, source.last_error_message)
  end
end
