class TextFragmentsController < AdminController
  before_action :set_text_fragment, only: [:show, :edit, :update]

  def index
    @text_fragments = TextFragment.ordered
  end

  def show
  end

  def edit
  end

  def update
    if @text_fragment.update(text_fragment_params)
      redirect_to text_fragments_path, notice: 'Text fragment updated successfully.'
    else
      render :edit, status: :unprocessable_content
    end
  end

  # Seed the default text fragments
  def seed
    seed_fragments
    redirect_to text_fragments_path, notice: 'Text fragments seeded successfully.'
  end

  private

  def set_text_fragment
    @text_fragment = TextFragment.find(params[:id])
  end

  def text_fragment_params
    params.require(:text_fragment).permit(:title, :content)
  end

  def seed_fragments
    TextFragment.ensure_exists!(
      key: 'member_help',
      title: 'Member Help',
      content: <<~HTML
        <h4>Welcome to Your Member Profile!</h4>
        <p>This is your member dashboard where you can view and manage your membership information.</p>
        
        <h5>What you'll find here:</h5>
        <ul>
          <li><strong>Profile Information</strong> - Your contact details and account settings</li>
          <li><strong>Membership Status</strong> - Your current membership status and payment history</li>
          <li><strong>Training</strong> - View your training certifications and available courses</li>
          <li><strong>Access</strong> - Your RFID key fobs and access history</li>
        </ul>
        
        <h5>Need help?</h5>
        <p>If you have questions about your membership or need assistance, please contact us.</p>
      HTML
    )

    TextFragment.ensure_exists!(
      key: 'motd',
      title: 'Message of the Day',
      content: '' # Empty by default - will only display when content is added
    )

    TextFragment.ensure_exists!(
      key: 'navbar_help',
      title: 'Navbar Help',
      content: <<~HTML
        <h4>Member Manager Help</h4>
        <p>Welcome to Member Manager. This page provides an overview of the system and how to use it.</p>

        <h5>Members</h5>
        <p>View and manage all members, their profiles, membership status, and payment history. Use the search bar to find members quickly.</p>

        <h5>Payments</h5>
        <p>PayPal, Recharge, and Ko-Fi payments are synced automatically. You can also manually import payments and link them to members.</p>

        <h5>Access</h5>
        <p>Manage access controllers, RFID readers, and view access logs. Access controllers sync RFID keys to door controllers via SSH scripts.</p>

        <h5>Training</h5>
        <p>Track which members are trained on equipment and who can train others. Training topics are configured in Settings.</p>

        <h5>Settings</h5>
        <p>Configure membership plans, email templates, text fragments, applications, webhooks, and integrations with Authentik, Slack, and Google Sheets.</p>

        <hr>
        <p class="text-muted">This help text can be edited in <strong>Settings &gt; Text Fragments &gt; Navbar Help</strong>.</p>
      HTML
    )

    TextFragment.ensure_exists!(
      key: 'apply_for_membership',
      title: 'Apply For Membership',
      content: <<~HTML
        <h1 class="h3 mb-4">Hello!</h1>

        <p>
          We hope you enjoyed your recent visit to PDX Hackerspace! It was a pleasure having you, 
          and we're excited about the possibility of you joining our community.
        </p>

        <p>
          As we mentioned during your visit, becoming a member of PDX Hackerspace gives you access 
          to our tools, equipment, and resources, as well as the opportunity to learn from and 
          collaborate with other talented individuals in the community. We believe in building a 
          strong and trusting community, which is why we require an in-person visit and tour for 
          potential members before sharing our membership application link.
        </p>

        <p>
          To apply for membership, please complete the PDX Hackerspace Membership Application using the following link:
        </p>

        <div class="text-center my-4">
          <a href="https://forms.gle/mHEQMGVzTNzCbyq26" class="btn btn-primary btn-lg" target="_blank" rel="noopener">
            https://forms.gle/mHEQMGVzTNzCbyq26
          </a>
        </div>

        <div class="alert alert-warning">
          <i class="bi bi-exclamation-triangle me-2"></i>
          <strong>Please note:</strong> This application link is exclusively for those who have visited us in person, 
          so please do not share it with others. We appreciate your understanding and cooperation in helping us 
          maintain the integrity of our community.
        </div>

        <p>
          Once you've submitted your application, our team will review it and get back to you shortly.
        </p>

        <p>
          If you have any questions or need further assistance, please don't hesitate to reach out to us at 
          <a href="mailto:info@pdxhs.org">info@pdxhs.org</a> or call us at <strong>503-560-3551</strong>.
        </p>

        <p class="mb-0">
          Thank you again for your interest in PDX Hackerspace, and we look forward to the possibility of having 
          you as a member of our vibrant community.
        </p>
      HTML
    )
  end
end
