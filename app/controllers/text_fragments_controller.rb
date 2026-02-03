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
  end
end
