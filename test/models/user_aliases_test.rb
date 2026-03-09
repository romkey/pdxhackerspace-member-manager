require 'test_helper'

class UserAliasesTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update_columns(aliases: [])
  end

  # ─── add_alias ─────────────────────────────────────────────────────

  test 'add_alias adds a new alias' do
    assert @user.add_alias('Johnny One')
    assert_includes @user.aliases, 'Johnny One'
  end

  test 'add_alias rejects blank names' do
    assert_not @user.add_alias('')
    assert_not @user.add_alias(nil)
    assert_not @user.add_alias('   ')
  end

  test 'add_alias rejects name matching full_name case-insensitively' do
    assert_not @user.add_alias(@user.full_name)
    assert_not @user.add_alias(@user.full_name.upcase)
    assert_not @user.add_alias(@user.full_name.downcase)
  end

  test 'add_alias rejects duplicate alias case-insensitively' do
    @user.add_alias('Johnny One')
    assert_not @user.add_alias('johnny one')
    assert_not @user.add_alias('JOHNNY ONE')
    assert_equal 1, @user.aliases.size
  end

  test 'add_alias strips whitespace' do
    @user.add_alias('  Padded Name  ')
    assert_includes @user.aliases, 'Padded Name'
  end

  # ─── add_alias! ────────────────────────────────────────────────────

  test 'add_alias! persists to database' do
    @user.add_alias!('Persistent Alias')
    @user.reload
    assert_includes @user.aliases, 'Persistent Alias'
  end

  test 'add_alias! returns false for duplicate' do
    @user.add_alias!('First Alias')
    result = @user.add_alias!('first alias')
    assert_not result
  end

  # ─── aliases_text virtual attribute ────────────────────────────────

  test 'aliases_text returns comma-separated string' do
    @user.update_columns(aliases: ['Alias One', 'Alias Two'])
    @user.reload
    assert_equal 'Alias One, Alias Two', @user.aliases_text
  end

  test 'aliases_text= sets aliases from comma-separated string' do
    @user.aliases_text = 'One, Two, Three'
    assert_equal %w[One Two Three], @user.aliases
  end

  test 'aliases_text= deduplicates entries' do
    @user.aliases_text = 'Same, Same, Same'
    assert_equal ['Same'], @user.aliases
  end

  test 'aliases_text= handles blank values' do
    @user.aliases_text = ''
    assert_equal [], @user.aliases
  end
end
