require 'test_helper'

class LoginLinkExpirationJobTest < ActiveJob::TestCase
  test 'clears expired login tokens' do
    user = users(:one)
    user.update!(
      login_token: SecureRandom.alphanumeric(64),
      login_token_expires_at: 1.hour.ago
    )

    LoginLinkExpirationJob.perform_now

    user.reload
    assert_nil user.login_token
    assert_nil user.login_token_expires_at
  end

  test 'does not clear active login tokens' do
    user = users(:one)
    user.update!(
      login_token: SecureRandom.alphanumeric(64),
      login_token_expires_at: 5.days.from_now
    )

    LoginLinkExpirationJob.perform_now

    user.reload
    assert_not_nil user.login_token
  end

  test 'enqueues expiration email for expired tokens' do
    user = users(:one)
    user.update!(
      login_token: SecureRandom.alphanumeric(64),
      login_token_expires_at: 1.hour.ago
    )

    assert_difference 'QueuedMail.count', 1 do
      LoginLinkExpirationJob.perform_now
    end
  end

  test 'does not enqueue email for active tokens' do
    user = users(:one)
    user.update!(
      login_token: SecureRandom.alphanumeric(64),
      login_token_expires_at: 5.days.from_now
    )

    assert_no_difference 'QueuedMail.count' do
      LoginLinkExpirationJob.perform_now
    end
  end

  test 'handles users without tokens' do
    assert_nil LoginLinkExpirationJob.perform_now
  end
end
