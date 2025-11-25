# SPDX-FileCopyrightText: 2025 John Romkey
#
# SPDX-License-Identifier: CC0-1.0

class RfidReadersController < AdminController
  skip_before_action :verify_authenticity_token, only: [:regenerate_key]
  before_action :set_rfid_reader, only: [:show, :edit, :update, :destroy, :regenerate_key]

  def index
    @rfid_readers = RfidReader.order(:name)
  end

  def show
  end

  def new
    @rfid_reader = RfidReader.new
  end

  def create
    @rfid_reader = RfidReader.new(rfid_reader_params)

    if @rfid_reader.save
      redirect_to rfid_readers_path, notice: 'RFID reader created successfully.'
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @rfid_reader.update(rfid_reader_params)
      redirect_to rfid_readers_path, notice: 'RFID reader updated successfully.'
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @rfid_reader.destroy
    redirect_to rfid_readers_path, notice: 'RFID reader deleted successfully.'
  end

  def regenerate_key
    @rfid_reader.generate_key!
    
    respond_to do |format|
      format.html { redirect_to edit_rfid_reader_path(@rfid_reader), notice: 'Key regenerated successfully.' }
      format.json { render json: { key: @rfid_reader.key } }
    end
  end

  private

  def set_rfid_reader
    @rfid_reader = RfidReader.find(params[:id])
  end

  def rfid_reader_params
    params.require(:rfid_reader).permit(:name, :note)
  end
end

