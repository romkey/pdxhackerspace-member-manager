require 'test_helper'

class UserProfileVisibilityTest < ActionDispatch::IntegrationTest
  setup do
    @public_user = users(:public_profile_user)
    @private_user = users(:private_profile_user)
    @members_user = users(:one)
    @member_with_account = users(:member_with_local_account)
  end

  # ==========================================
  # PUBLIC VIEW TESTS (not logged in)
  # ==========================================

  test 'anonymous user can view public profile' do
    get user_path(@public_user)
    assert_response :success
    assert_match @public_user.display_name, response.body
  end

  test 'anonymous user sees minimal info on public profile' do
    get user_path(@public_user)
    assert_response :success

    # Should see basic info
    assert_match @public_user.display_name, response.body
    assert_match @public_user.bio, response.body if @public_user.bio.present?

    # Should NOT see membership status info
    assert_no_match(/Active.*Inactive/i, response.body) # status panel
    assert_no_match(/Payment Type/i, response.body)
    assert_no_match(/Membership Status/i, response.body)
    assert_no_match(/Trained on/i, response.body)
    assert_no_match(/Can train/i, response.body)
  end

  test 'anonymous user cannot view private profile' do
    get user_path(@private_user)
    assert_redirected_to login_path
  end

  test 'anonymous user cannot view members-only profile' do
    get user_path(@members_user)
    assert_redirected_to login_path
  end

  # ==========================================
  # MEMBERS VIEW TESTS (logged in, non-admin)
  # ==========================================

  test 'logged in member can view members-only profile' do
    sign_in_as_member
    get user_path(@members_user)
    assert_response :success
    assert_match @members_user.display_name, response.body
  end

  test 'logged in member can view public profile' do
    sign_in_as_member
    get user_path(@public_user)
    assert_response :success
    assert_match @public_user.display_name, response.body
  end

  test 'logged in member cannot view private profile of another user' do
    sign_in_as_member
    get user_path(@private_user)
    # Should redirect to their own profile
    assert_redirected_to user_path(@member_with_account)
  end

  test 'logged in member sees training info but not status panel on other profiles' do
    sign_in_as_member
    get user_path(@members_user)
    assert_response :success

    # Should see training info
    assert_match /Trained on/i, response.body
    assert_match /Can train/i, response.body

    # Should NOT see status panel info
    assert_no_match(/Payment Type/i, response.body)
    assert_no_match(/Dues Status/i, response.body)
    assert_no_match(/Membership Plan/i, response.body)
  end

  test 'logged in member does not see tabs on other member profiles' do
    sign_in_as_member
    get user_path(@members_user)
    assert_response :success

    # Should not see nav tabs
    assert_no_match(/nav-tabs/, response.body)
    assert_no_match(/Payment History/i, response.body)
  end

  # ==========================================
  # SELF VIEW TESTS (user viewing own profile)
  # ==========================================

  test 'user can view their own profile' do
    sign_in_as_member
    get user_path(@member_with_account)
    assert_response :success
    assert_match @member_with_account.display_name, response.body
  end

  test 'user sees tabs on their own profile' do
    sign_in_as_member
    get user_path(@member_with_account)
    assert_response :success

    # Should see nav tabs
    assert_match /nav-tabs/, response.body
    assert_match /Profile/, response.body
    assert_match /Payment History/i, response.body
  end

  test 'user sees status panel on their own profile' do
    sign_in_as_member
    get user_path(@member_with_account)
    assert_response :success

    # Should see status panel
    assert_match /Payment Type/i, response.body
    assert_match /Membership Status/i, response.body
  end

  test 'user can access payments tab on their own profile' do
    sign_in_as_member
    get user_path(@member_with_account, tab: :payments)
    assert_response :success
    assert_match /Payment History/i, response.body
  end

  test 'user sees edit button on their own profile' do
    sign_in_as_member
    get user_path(@member_with_account)
    assert_response :success
    assert_match /Edit Profile/i, response.body
  end

  # ==========================================
  # ADMIN VIEW TESTS
  # ==========================================

  test 'admin can view any profile' do
    sign_in_as_admin
    get user_path(@private_user)
    assert_response :success
    assert_match @private_user.display_name, response.body
  end

  test 'admin sees all tabs' do
    sign_in_as_admin
    get user_path(@members_user)
    assert_response :success

    assert_match /nav-tabs/, response.body
    assert_match /Profile/, response.body
    assert_match /Payments/, response.body
    assert_match /Access/, response.body
    assert_match /Journal/, response.body
  end

  test 'admin sees full profile info including notes and RFID' do
    sign_in_as_admin
    get user_path(@members_user)
    assert_response :success

    assert_match /Authentik ID/i, response.body
    assert_match /Notes/i, response.body
    assert_match /RFID Keys/i, response.body
    assert_match /Last synced/i, response.body
  end

  test 'admin can access all tabs' do
    sign_in_as_admin

    get user_path(@members_user, tab: :profile)
    assert_response :success

    get user_path(@members_user, tab: :payments)
    assert_response :success

    get user_path(@members_user, tab: :access)
    assert_response :success

    get user_path(@members_user, tab: :journal)
    assert_response :success
  end

  # ==========================================
  # VIEW PREVIEW TESTS
  # ==========================================

  test 'admin can preview profile as public' do
    sign_in_as_admin
    get user_path(@members_user, view_as: :public)
    assert_response :success

    # Should see preview selector
    assert_match /Preview profile as/i, response.body
    assert_match /Previewing/, response.body

    # Should NOT see admin-only info
    assert_no_match(/Authentik ID/i, response.body)
    assert_no_match(/Notes/i, response.body)
    assert_no_match(/nav-tabs/, response.body)
  end

  test 'admin can preview profile as members' do
    sign_in_as_admin
    get user_path(@members_user, view_as: :members)
    assert_response :success

    # Should see training info
    assert_match /Trained on/i, response.body

    # Should NOT see status panel
    assert_no_match(/Payment Type/i, response.body)
    assert_no_match(/nav-tabs/, response.body)
  end

  test 'admin can preview profile as self' do
    sign_in_as_admin
    get user_path(@members_user, view_as: :self)
    assert_response :success

    # Should see self-view tabs
    assert_match /nav-tabs/, response.body
    assert_match /Payment History/i, response.body

    # Should NOT see admin tabs
    assert_no_match(/Access.*Journal/i, response.body)
  end

  test 'user can preview their own profile as public' do
    sign_in_as_member
    get user_path(@member_with_account, view_as: :public)
    assert_response :success

    # Should see preview selector
    assert_match /Preview profile as/i, response.body

    # Should see minimal public info
    assert_no_match(/Trained on/i, response.body)
    assert_no_match(/Payment Type/i, response.body)
  end

  test 'user can preview their own profile as members' do
    sign_in_as_member
    get user_path(@member_with_account, view_as: :members)
    assert_response :success

    # Should see training info but no status panel
    assert_match /Trained on/i, response.body
    assert_no_match(/Payment Type/i, response.body)
  end

  test 'user cannot preview as admin' do
    sign_in_as_member
    get user_path(@member_with_account, view_as: :admin)
    assert_response :success

    # Should fall back to self view, not admin view
    assert_no_match(/Authentik ID/i, response.body)
    assert_no_match(/Notes/i, response.body)
  end

  test 'user cannot preview other users profiles' do
    sign_in_as_member
    get user_path(@members_user, view_as: :public)
    assert_response :success

    # Should not see preview selector (they're not admin or owner)
    assert_no_match(/Preview profile as/i, response.body)
  end

  private

  def sign_in_as_admin
    account = local_accounts(:active_admin)
    post local_login_path, params: {
      session: {
        email: account.email,
        password: 'localpassword123'
      }
    }
  end

  def sign_in_as_member
    account = local_accounts(:regular_member)
    post local_login_path, params: {
      session: {
        email: account.email,
        password: 'memberpassword123'
      }
    }
  end
end
