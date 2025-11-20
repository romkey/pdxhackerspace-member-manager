require 'test_helper'

class LocalAccountTest < ActiveSupport::TestCase
  test 'requires a unique email' do
    existing = local_accounts(:active_admin)
    duplicate = LocalAccount.new(email: existing.email, password: 'anotherpassword123')

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:email], 'has already been taken'
  end

  test 'enforces minimum password length' do
    account = LocalAccount.new(email: 'new@example.com', password: 'short')

    assert_not account.valid?
    assert_includes account.errors[:password], 'is too short (minimum is 12 characters)'
  end
end
