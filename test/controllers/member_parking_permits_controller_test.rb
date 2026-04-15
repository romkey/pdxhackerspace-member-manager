require 'test_helper'

class MemberParkingPermitsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_local_auth_enabled = Rails.application.config.x.local_auth.enabled
    Rails.application.config.x.local_auth.enabled = true
  end

  teardown do
    Rails.application.config.x.local_auth.enabled = @original_local_auth_enabled
  end

  test 'member can open new permit form' do
    sign_in_as_member

    get new_member_parking_permit_path
    assert_response :success
    assert_match(/New Parking Permit/i, response.body)
  end

  test 'member can create own parking permit' do
    sign_in_as_member
    member = User.find_by(authentik_id: "local:#{local_accounts(:regular_member).id}")

    assert_difference 'ParkingNotice.count', 1 do
      post member_parking_permits_path, params: {
        parking_notice: {
          description: 'My project',
          location: 'Woodshop',
          location_detail: 'Bench A',
          expires_at: 3.days.from_now.strftime('%Y-%m-%dT%H:%M')
        }
      }
    end

    notice = ParkingNotice.order(:created_at).last
    assert_equal 'permit', notice.notice_type
    assert_equal 'active', notice.status
    assert_equal member.id, notice.user_id
    assert_equal member.id, notice.issued_by_id
    assert_redirected_to user_path(member, tab: :parking)
  end

  test 'anonymous user cannot access member permit form' do
    get new_member_parking_permit_path
    assert_redirected_to login_path
  end

  private

  def sign_in_as_member
    post local_login_path, params: {
      session: { email: local_accounts(:regular_member).email, password: 'memberpassword123' }
    }
  end
end
