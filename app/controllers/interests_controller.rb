class InterestsController < AdminController
  before_action :set_interest, only: %i[edit update destroy members merge_form merge approve]

  SEED_INTERESTS = [
    # Electronics & Hardware
    'Electronics', 'Soldering', 'PCB Design', 'Arduino', 'Raspberry Pi',
    '3D Printing', 'CNC Machining', 'Laser Cutting', 'Robotics', 'Embedded Systems',
    'Amateur Radio (HAM)', 'Drone Building', '3D Scanning',
    # Software & Infosec
    'Information Security', 'Penetration Testing', 'CTF Competitions',
    'Cryptography', 'Reverse Engineering', 'Open Source Software',
    'Linux/Unix', 'Networking', 'Lock Picking',
    # Crafting
    'Sewing', 'Knitting', 'Leatherworking', 'Jewelry Making', 'Ceramics/Pottery',
    'Resin Casting', 'Screen Printing', 'Embroidery', 'Bookbinding', 'Soap Making',
    # Fabrication
    'Woodworking', 'Metalworking', 'Welding', 'Plastics', 'CAD/CAM Design',
    'Foam Fabrication', 'Composites',
    # Art & Design
    'Graphic Design', 'Digital Art', 'Photography', 'Painting', 'Illustration',
    # Science & Other
    'Biohacking', 'Mycology', 'Hydroponics', 'Astronomy',
    'Music Electronics', 'Cosplay/Props'
  ].freeze

  def index
    @filter       = params[:filter]
    @interests    = Interest.alphabetical.includes(:user_interests)
    @interests    = @interests.needs_review if @filter == 'needs_review'
    @new_interest = Interest.new
    @already_seeded = Interest.seeded?
  end

  def new
    @interest = Interest.new
  end

  def edit; end

  def create
    @interest = Interest.new(interest_params)
    if @interest.save
      redirect_to interests_path, notice: "'#{@interest.name}' added."
    else
      @interests      = Interest.alphabetical.includes(:user_interests)
      @new_interest   = @interest
      @already_seeded = Interest.seeded?
      render :index, status: :unprocessable_content
    end
  end

  def update
    if @interest.update(interest_params)
      redirect_to interests_path, notice: 'Interest updated.'
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    name = @interest.name
    @interest.destroy!
    redirect_to interests_path, notice: "'#{name}' removed."
  end

  def approve
    @interest.update!(needs_review: false)
    redirect_back_or_to(interests_path, notice: "'#{@interest.name}' approved.")
  end

  def members
    @members = @interest.users.includes(:user_interests).order(:full_name)
  end

  def merge_form
    @target_interests = Interest.alphabetical.where.not(id: @interest.id)
  end

  def merge
    target = Interest.find(params[:target_interest_id])

    @interest.user_interests.each do |ui|
      ui.update_columns(interest_id: target.id) unless UserInterest.exists?(user_id: ui.user_id, interest_id: target.id)
    end

    name = @interest.name
    @interest.reload.destroy!
    redirect_to interests_path, notice: "'#{name}' merged into '#{target.name}'."
  rescue ActiveRecord::RecordNotFound
    redirect_to interests_path, alert: 'Target interest not found.'
  end

  def seed
    if Interest.seeded?
      redirect_to interests_path, alert: 'Interests have already been seeded.'
      return
    end

    created = 0
    SEED_INTERESTS.each do |name|
      Interest.find_or_create_by!(name: name) do |i|
        i.seeded       = true
        i.needs_review = false
      end
      created += 1
    rescue ActiveRecord::RecordInvalid
      # skip duplicates that exist under a slightly different case
    end

    redirect_to interests_path, notice: "#{created} interests seeded successfully."
  end

  private

  def set_interest
    @interest = Interest.find(params[:id])
  end

  def interest_params
    params.expect(interest: [:name])
  end
end
