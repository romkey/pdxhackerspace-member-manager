require 'test_helper'

# Tests for SearchController.
#
# Admin search: existing behavior - returns users, Authentik users, sheet entries,
# Slack users, and payments.
#
# Member search: returns matching public/members-visible profiles, matching interests
# with their members, and matching training topics with trained members and trainers.
# Private profiles are never exposed.
class SearchControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_local_auth_enabled = Rails.application.config.x.local_auth.enabled
    Rails.application.config.x.local_auth.enabled = true
  end

  teardown do
    Rails.application.config.x.local_auth.enabled = @original_local_auth_enabled
  end

  # ── Authentication ──────────────────────────────────────────────────────────

  test 'unauthenticated request redirects to login' do
    get search_path, params: { q: 'anything' }
    assert_redirected_to login_path
  end

  # ── Admin search ────────────────────────────────────────────────────────────

  test 'admin can access search' do
    sign_in_as_admin
    get search_path, params: { q: 'example' }
    assert_response :success
  end

  test 'admin blank query renders no results' do
    sign_in_as_admin
    get search_path, params: { q: '' }
    assert_response :success
    assert_no_match(/Members \(/, response.body)
  end

  test 'admin search finds users by full name' do
    sign_in_as_admin
    get search_path, params: { q: 'Example User' }
    assert_response :success
    assert_match users(:one).display_name, response.body
    assert_match users(:two).display_name, response.body
  end

  test 'admin search shows admin sections (sheet entries, payments, etc.)' do
    sign_in_as_admin
    get search_path, params: { q: 'example' }
    assert_match(/Sheet Entries|Authentik Users|Slack Users|PayPal|Recharge/i, response.body)
  end

  # ── Member search – access ──────────────────────────────────────────────────

  test 'non-admin member can access search' do
    sign_in_as_member
    get search_path, params: { q: 'example' }
    assert_response :success
  end

  test 'member search does not show admin-only sections' do
    sign_in_as_member
    get search_path, params: { q: 'example' }
    assert_no_match(/Sheet Entries/i, response.body)
    assert_no_match(/Authentik Users/i, response.body)
    assert_no_match(/PayPal Payments/i, response.body)
  end

  test 'member blank query renders help text' do
    sign_in_as_member
    get search_path, params: { q: '' }
    assert_response :success
    assert_match(/search term/i, response.body)
  end

  test 'member search with no matches shows no results message' do
    sign_in_as_member
    get search_path, params: { q: 'xyzzy_no_match_999' }
    assert_response :success
    assert_match(/No results/i, response.body)
  end

  # ── Member search – profile matching ───────────────────────────────────────

  test 'member search returns members-visible profiles by name' do
    sign_in_as_member
    # users(:one) full_name = "Example User One", profile_visibility: members
    get search_path, params: { q: 'Example User' }
    assert_response :success
    assert_match users(:one).display_name, response.body
    assert_match users(:two).display_name, response.body
  end

  test 'member search returns public profiles by name' do
    sign_in_as_member
    # users(:public_profile_user) full_name = "Public Profile User", profile_visibility: public
    get search_path, params: { q: 'Public Profile' }
    assert_response :success
    assert_match users(:public_profile_user).display_name, response.body
  end

  test 'member search returns profiles matching by username' do
    sign_in_as_member
    # users(:one) username = "exampleuserone"
    get search_path, params: { q: 'exampleuserone' }
    assert_response :success
    assert_match users(:one).display_name, response.body
  end

  test 'member search does not return private profiles' do
    sign_in_as_member
    # users(:private_profile_user) full_name = "Private Profile User", profile_visibility: private
    get search_path, params: { q: 'Private Profile' }
    assert_response :success
    assert_no_match users(:private_profile_user).display_name, response.body
  end

  # ── Member search – interest matching ──────────────────────────────────────

  test 'member search returns matching interests' do
    sign_in_as_member
    # interests(:electronics) name = "Electronics"
    # users(:one) and users(:two) both have electronics, both profile_visibility: members
    get search_path, params: { q: 'Electronics' }
    assert_response :success
    assert_match(/Interests/i, response.body)
    assert_match interests(:electronics).name, response.body
  end

  test 'member interest results show members who have that interest' do
    sign_in_as_member
    get search_path, params: { q: 'Electronics' }
    assert_match users(:one).display_name, response.body
    assert_match users(:two).display_name, response.body
  end

  test 'member interest result excludes members with private profiles' do
    sign_in_as_member
    users(:private_profile_user).interests << interests(:electronics)
    get search_path, params: { q: 'Electronics' }
    assert_no_match users(:private_profile_user).display_name, response.body
  end

  test 'member interest result is omitted when all matching members have private profiles' do
    sign_in_as_member
    # Create a new interest only held by the private-profile user
    private_interest = Interest.create!(name: 'PrivateOnlyInterest')
    users(:private_profile_user).interests << private_interest

    get search_path, params: { q: 'PrivateOnlyInterest' }
    assert_response :success
    # The interest section should not appear since no visible members have it
    # (the term appears in the search input value, so check the results area specifically)
    assert_match(/No results found/i, response.body)
  end

  # ── Member search – training topic matching ─────────────────────────────────

  test 'member search returns matching training topics' do
    sign_in_as_member
    # training_topics(:laser_cutting) name = "Laser Cutting"
    Training.create!(
      trainee: users(:one),
      trainer: nil,
      training_topic: training_topics(:laser_cutting),
      trained_at: 1.week.ago
    )

    get search_path, params: { q: 'Laser' }
    assert_response :success
    assert_match(/Training Topics/i, response.body)
    assert_match training_topics(:laser_cutting).name, response.body
  end

  test 'member search shows trained members for a training topic' do
    sign_in_as_member
    # users(:one) has profile_visibility: members
    Training.create!(
      trainee: users(:one),
      trainer: nil,
      training_topic: training_topics(:laser_cutting),
      trained_at: 1.week.ago
    )

    get search_path, params: { q: 'Laser' }
    assert_match users(:one).display_name, response.body
    assert_match(/Trained in this topic/i, response.body)
  end

  test 'member search shows trainers for a training topic' do
    sign_in_as_member
    # users(:two) is a trainer for woodworking, profile_visibility: members
    TrainerCapability.create!(user: users(:two), training_topic: training_topics(:woodworking))

    get search_path, params: { q: 'Woodwork' }
    assert_match users(:two).display_name, response.body
    assert_match(/Can train others/i, response.body)
  end

  test 'member training topic result excludes trained members with private profiles' do
    sign_in_as_member
    Training.create!(
      trainee: users(:private_profile_user),
      trainer: nil,
      training_topic: training_topics(:laser_cutting),
      trained_at: 1.week.ago
    )

    get search_path, params: { q: 'Laser' }
    # Topic should not appear at all since the only trained member is private
    # (trainers list is also empty)
    assert_no_match users(:private_profile_user).display_name, response.body
  end

  test 'member training topic result is omitted when only private members are involved' do
    sign_in_as_member
    Training.create!(
      trainee: users(:private_profile_user),
      trainer: nil,
      training_topic: training_topics(:electronics),
      trained_at: 1.week.ago
    )

    get search_path, params: { q: 'Electronics' }
    # The training_topics(:electronics) match should not add a training card
    # (only trained member is private; no trainers)
    assert_no_match(/Trained in this topic/i, response.body)
  end

  private

  def sign_in_as_admin
    post local_login_path, params: {
      session: { email: local_accounts(:active_admin).email, password: 'localpassword123' }
    }
  end

  def sign_in_as_member
    post local_login_path, params: {
      session: { email: local_accounts(:regular_member).email, password: 'memberpassword123' }
    }
  end
end
