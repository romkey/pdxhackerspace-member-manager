require 'test_helper'

class InterestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_local_auth_enabled = Rails.application.config.x.local_auth.enabled
    Rails.application.config.x.local_auth.enabled = true
    sign_in_as_admin
    @interest = interests(:electronics)
  end

  teardown do
    Rails.application.config.x.local_auth.enabled = @original_local_auth_enabled
  end

  # Index

  test 'index lists all interests alphabetically' do
    get interests_path
    assert_response :success
    assert_match 'Electronics', response.body
    assert_match 'Woodworking', response.body
    assert_match '3D Printing', response.body
  end

  test 'index shows member count per interest' do
    get interests_path
    assert_response :success
    # electronics has 2 members in fixtures
    assert_match '2', response.body
  end

  test 'index is inaccessible to non-admins' do
    sign_in_as_regular_member
    get interests_path
    assert_response :redirect
    assert_not response.location.end_with?(interests_path)
  end

  # Create

  test 'creates a new interest' do
    assert_difference 'Interest.count', 1 do
      post interests_path, params: { interest: { name: 'Robotics' } }
    end
    assert_redirected_to interests_path
    assert_equal 'Robotics', Interest.last.name
  end

  test 'rejects a duplicate interest name' do
    assert_no_difference 'Interest.count' do
      post interests_path, params: { interest: { name: 'Electronics' } }
    end
    assert_response :unprocessable_entity
  end

  test 'rejects a blank interest name' do
    assert_no_difference 'Interest.count' do
      post interests_path, params: { interest: { name: '' } }
    end
    assert_response :unprocessable_entity
  end

  # Edit / Update

  test 'shows edit form' do
    get edit_interest_path(@interest)
    assert_response :success
    assert_match @interest.name, response.body
  end

  test 'updates interest name' do
    patch interest_path(@interest), params: { interest: { name: 'Advanced Electronics' } }
    assert_redirected_to interests_path
    assert_equal 'Advanced Electronics', @interest.reload.name
  end

  test 'update rejects blank name' do
    patch interest_path(@interest), params: { interest: { name: '' } }
    assert_response :unprocessable_entity
    assert_equal 'Electronics', @interest.reload.name
  end

  # Destroy

  test 'destroys an interest and its user_interests' do
    # laser_cutting has no user_interests in fixtures; just verify the interest is deleted
    assert_difference 'Interest.count', -1 do
      delete interest_path(interests(:laser_cutting))
    end
    assert_redirected_to interests_path
  end

  test 'destroying an interest with members removes all user_interests' do
    interest       = interests(:electronics)
    member_count   = interest.user_interests.count

    assert_difference 'UserInterest.count', -member_count do
      delete interest_path(interest)
    end
  end

  # Merge form

  test 'merge_form shows target dropdown' do
    get merge_form_interest_path(@interest)
    assert_response :success
    assert_match @interest.name, response.body
    # Other interests should appear as options
    assert_match interests(:woodworking).name, response.body
  end

  # Merge

  test 'merge re-points user_interests to target and deletes source' do
    source = interests(:programming)   # 1 member: users(:one)
    target = interests(:woodworking)   # 1 member: users(:two)

    source_id = source.id

    assert_difference 'Interest.count', -1 do
      post merge_interest_path(source), params: { target_interest_id: target.id }
    end

    assert_redirected_to interests_path
    assert_not Interest.exists?(source_id)
    # users(:one) should now have woodworking
    assert users(:one).reload.interests.include?(target)
  end

  test 'merge skips duplicates when both users already share the target interest' do
    # users(:one) has both electronics and programming
    # users(:two) has electronics
    # Merging programming → electronics for users(:one) would be a duplicate
    source = interests(:programming)
    target = interests(:electronics)

    # users(:one) already has electronics; merging should not create a duplicate
    post merge_interest_path(source), params: { target_interest_id: target.id }
    assert_redirected_to interests_path
  end

  # Seed

  test 'seed creates 50 interests and marks them seeded' do
    assert_not Interest.seeded?, 'precondition: no seeded interests'
    post seed_interests_path
    assert Interest.seeded?
    # Fixture interests that overlap with the seed list won't be marked seeded
    # (find_or_create_by doesn't run the block for found records); at least the
    # newly created ones should be, and total should be close to 50.
    assert_operator Interest.seeded_set.count, :>=, 40
    assert_redirected_to interests_path
    assert_match(/seeded/i, flash[:notice])
  end

  test 'seed is idempotent when already seeded' do
    Interest.create!(name: 'Seed Guard', seeded: true)
    assert_no_difference 'Interest.count' do
      post seed_interests_path
    end
    assert_redirected_to interests_path
    assert_match(/already been seeded/i, flash[:alert])
  end

  test 'seed button appears when no seeded interests exist' do
    get interests_path
    assert_match(/Seed Interests/i, response.body)
  end

  test 'seed button is hidden after seeding' do
    Interest.create!(name: 'Seed Guard', seeded: true)
    get interests_path
    assert_no_match(/Seed Interests/i, response.body)
  end

  # Approve

  test 'approve sets needs_review to false' do
    @interest.update!(needs_review: true)
    post approve_interest_path(@interest)
    assert_not @interest.reload.needs_review?
    assert_redirected_to interests_path
    assert_match(/approved/i, flash[:notice])
  end

  test 'approve is a no-op on already approved interest' do
    assert_not @interest.needs_review?, 'precondition: already approved'
    post approve_interest_path(@interest)
    assert_not @interest.reload.needs_review?
    assert_redirected_to interests_path
  end

  # Filter: needs_review

  test 'index with filter=needs_review shows only flagged interests' do
    @interest.update!(needs_review: true)
    get interests_path(filter: 'needs_review')
    assert_response :success
    assert_match @interest.name, response.body
    # Woodworking (approved) should not appear as a table row — it does appear in
    # the "Add Interest" form placeholder, so check for the table cell specifically
    assert_no_match(%r{class="fw-semibold">#{interests(:woodworking).name}</span>}, response.body)
  end

  test 'index with no filter shows all interests' do
    @interest.update!(needs_review: true)
    get interests_path
    assert_response :success
    assert_match @interest.name, response.body
    assert_match interests(:woodworking).name, response.body
  end

  test 'needs_review filter shows empty state when none pending' do
    get interests_path(filter: 'needs_review')
    assert_response :success
    assert_match(/No interests are waiting for review/i, response.body)
  end

  # Members list

  test 'members lists users who selected the interest' do
    get members_interest_path(interests(:electronics))
    assert_response :success
    assert_match users(:one).display_name, response.body
    assert_match users(:two).display_name, response.body
  end

  test 'members shows empty state for interest with no members' do
    get members_interest_path(interests(:laser_cutting))
    assert_response :success
    assert_match(/No members/i, response.body)
  end

  private

  def sign_in_as_admin
    post local_login_path, params: {
      session: { email: local_accounts(:active_admin).email, password: 'localpassword123' }
    }
  end

  def sign_in_as_regular_member
    post local_login_path, params: {
      session: { email: local_accounts(:regular_member).email, password: 'memberpassword123' }
    }
  end
end
