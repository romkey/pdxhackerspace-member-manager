class RfidsController < AdminController
  def new
    @rfid = Rfid.new
    @users = User.ordered_by_display_name
    @building_access_topic = TrainingTopic.find_by("LOWER(name) LIKE ?", "%building access%")
    @trained_user_ids = if @building_access_topic
                          Training.where(training_topic: @building_access_topic).pluck(:trainee_id).to_set
                        else
                          Set.new
                        end
  end

  def create
    @rfid = Rfid.new(rfid_params)

    if @rfid.save
      training_added = false
      if params[:add_training] == '1'
        training_added = add_building_access_training(@rfid.user)
      end
      notice = "Key fob added successfully for #{@rfid.user.display_name}."
      notice += " Building Access training also recorded." if training_added
      redirect_to user_path(@rfid.user), notice: notice
    else
      @users = User.ordered_by_display_name
      @building_access_topic = TrainingTopic.find_by("LOWER(name) LIKE ?", "%building access%")
      @trained_user_ids = if @building_access_topic
                            Training.where(training_topic: @building_access_topic).pluck(:trainee_id).to_set
                          else
                            Set.new
                          end
      flash.now[:alert] = 'Unable to add key fob.'
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @rfid = Rfid.find(params[:id])
    user = @rfid.user
    @rfid.destroy!
    redirect_to user_path(user), notice: 'Key fob removed.'
  end

  private

  def rfid_params
    params.require(:rfid).permit(:user_id, :rfid, :notes)
  end

  def add_building_access_training(user)
    topic = TrainingTopic.find_by("LOWER(name) LIKE ?", "%building access%")
    return false unless topic
    return false if Training.exists?(trainee: user, training_topic: topic)

    training = Training.create!(
      trainee: user,
      trainer: current_user,
      training_topic: topic,
      trained_at: Time.current
    )

    Journal.create!(
      user: user,
      actor_user: current_user,
      action: 'training_added',
      changes_json: {
        'training' => {
          'topic' => topic.name,
          'trainer' => current_user.display_name,
          'trained_at' => training.trained_at.iso8601
        }
      },
      changed_at: Time.current,
      highlight: true
    )
    true
  end
end
