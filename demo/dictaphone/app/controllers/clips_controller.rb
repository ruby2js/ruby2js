class ClipsController < ApplicationController
  def index
    @clips = Clip.order(created_at: :desc)
  end

  def show
    @clip = Clip.find(params[:id])
  end

  def create
    @clip = Clip.new(clip_params)

    if @clip.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to clips_path }
      end
    else
      redirect_to clips_path, alert: "Could not save clip."
    end
  end

  def update
    @clip = Clip.find(params[:id])

    if @clip.update(clip_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to clips_path, notice: "Transcript updated." }
      end
    else
      redirect_to clips_path, alert: "Could not update clip."
    end
  end

  def destroy
    @clip = Clip.find(params[:id])
    @clip.audio.purge if @clip.audio.attached?
    @clip.destroy

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to clips_path, notice: "Clip deleted." }
    end
  end

  private

  def clip_params
    params.require(:clip).permit(:name, :transcript, :duration, :audio)
  end
end
