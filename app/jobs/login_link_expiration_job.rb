class LoginLinkExpirationJob < ApplicationJob
  queue_as :default

  def perform
    User.where.not(login_token: nil)
        .where(login_token_expires_at: ..Time.current)
        .find_each do |user|
      user.clear_login_token!
      QueuedMail.enqueue('login_link_expired', user, reason: 'Login link expired')
    end
  end
end
