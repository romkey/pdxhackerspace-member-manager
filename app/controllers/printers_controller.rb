class PrintersController < AdminController
  before_action :set_printer, only: %i[edit update destroy test_print]

  def index
    @printers = Printer.ordered
    @cups_printers = CupsService.available_printers
  end

  def new
    @printer = Printer.new
    @cups_printers = CupsService.available_printers
  end

  def edit
    @cups_printers = CupsService.available_printers
  end

  def create
    @printer = Printer.new(printer_params)
    if @printer.save
      redirect_to printers_path, notice: 'Printer added successfully.'
    else
      @cups_printers = CupsService.available_printers
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @printer.update(printer_params)
      redirect_to printers_path, notice: 'Printer updated successfully.'
    else
      @cups_printers = CupsService.available_printers
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @printer.destroy!
    redirect_to printers_path, notice: 'Printer removed.'
  end

  def test_print
    job_id = CupsService.test_print(
      @printer.cups_printer_name,
      cups_printer_server: @printer.cups_printer_server
    )
    redirect_to printers_path, notice: "Test page sent to #{@printer.name} (job #{job_id})."
  rescue CupsService::PrintError => e
    redirect_to printers_path, alert: "Test print failed: #{e.message}"
  end

  private

  def set_printer
    @printer = Printer.find(params[:id])
  end

  def printer_params
    params.expect(printer: %i[name cups_printer_server cups_printer_name description default_printer position])
  end
end
