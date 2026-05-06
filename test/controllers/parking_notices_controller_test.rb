require 'test_helper'

class ParkingNoticesControllerTest < ActionDispatch::IntegrationTest
  setup do
    ENV['LOCAL_AUTH_ENABLED'] = 'true'
    sign_in_as_admin
    @active_permit = parking_notices(:active_permit)
    @expired_ticket = parking_notices(:expired_ticket)
  end

  teardown do
    ENV.delete('LOCAL_AUTH_ENABLED')
  end

  # --- Index ---

  test 'index shows parking notices' do
    get parking_notices_url
    assert_response :success
    assert_select 'table'
  end

  test 'index filters by status' do
    get parking_notices_url(status: 'active')
    assert_response :success
  end

  test 'index filters by type' do
    get parking_notices_url(type: 'permit')
    assert_response :success
  end

  # --- Show ---

  test 'show displays parking notice' do
    get parking_notice_url(@active_permit)
    assert_response :success
    assert_select '.badge', text: 'Permit'
  end

  # --- New ---

  test 'new renders permit form' do
    get new_parking_notice_url(type: 'permit')
    assert_response :success
    assert_select 'input[name="parking_notice[notice_type]"][value="permit"]'
  end

  test 'member search includes email and username fields' do
    user = users(:one)

    get new_parking_notice_url(type: 'permit')
    assert_response :success

    assert_select '.pn-member-item[data-user-id=?][data-user-email=?][data-username=?]',
                  user.id.to_s, user.email, user.username
  end

  test 'new renders ticket form' do
    get new_parking_notice_url(type: 'ticket')
    assert_response :success
    assert_select 'input[name="parking_notice[notice_type]"][value="ticket"]'
  end

  # --- Create ---

  test 'create saves a valid permit' do
    user = users(:one)
    assert_difference 'ParkingNotice.count', 1 do
      post parking_notices_url, params: {
        parking_notice: {
          notice_type: 'permit',
          user_id: user.id,
          description: 'Test permit',
          location: 'Woodshop',
          expires_at: 7.days.from_now
        }
      }
    end
    assert_redirected_to parking_notice_path(ParkingNotice.last)
  end

  test 'create saves a ticket without user' do
    assert_difference 'ParkingNotice.count', 1 do
      post parking_notices_url, params: {
        parking_notice: {
          notice_type: 'ticket',
          description: 'Anonymous ticket',
          location: 'Main Area',
          expires_at: 3.days.from_now
        }
      }
    end
    assert_redirected_to parking_notice_path(ParkingNotice.last)
  end

  test 'create rejects invalid permit (missing user)' do
    assert_no_difference 'ParkingNotice.count' do
      post parking_notices_url, params: {
        parking_notice: {
          notice_type: 'permit',
          description: 'No user',
          expires_at: 7.days.from_now
        }
      }
    end
    assert_response :unprocessable_content
  end

  # --- Edit / Update ---

  test 'edit renders form' do
    get edit_parking_notice_url(@active_permit)
    assert_response :success
  end

  test 'update modifies notice' do
    patch parking_notice_url(@active_permit), params: {
      parking_notice: { description: 'Updated description' }
    }
    assert_redirected_to parking_notice_path(@active_permit)
    assert_equal 'Updated description', @active_permit.reload.description
  end

  # --- PDF Download ---

  test 'download_pdf returns a PDF' do
    get download_pdf_parking_notice_url(@active_permit)
    assert_response :success
    assert_equal 'application/pdf', response.content_type
  end

  # --- Clear ---

  test 'clear marks notice as cleared' do
    post clear_parking_notice_url(@active_permit)
    assert_redirected_to parking_notice_path(@active_permit)
    assert @active_permit.reload.cleared?
  end

  private

  def sign_in_as_admin
    Rails.application.config.x.local_auth.enabled = true
    post local_login_path, params: {
      session: { email: 'admin@example.com', password: 'localpassword123' }
    }
    User.find_by('authentik_id LIKE ?', 'local:%')&.tap { |u| u.update!(is_admin: true) }
  end
end
