class RfidsController < AdminController
  def new
    @rfid = Rfid.new
    @users = User.ordered_by_display_name
  end

  def create
    @rfid = Rfid.new(rfid_params)

    if @rfid.save
      redirect_to user_path(@rfid.user), notice: "Key fob added successfully for #{@rfid.user.display_name}."
    else
      @users = User.ordered_by_display_name
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
end
