class EdgesController < ApplicationController
  before_action :set_workflow

  def create
    @edge = @workflow.edges.build(edge_params)
    if @edge.save
      render json: @edge
    else
      render json: { errors: @edge.errors }, status: :unprocessable_entity
    end
  end

  def destroy
    @edge = @workflow.edges.find(params[:id])
    @edge.destroy
    head :ok
  end

  private

  def set_workflow
    @workflow = Workflow.find(params[:workflow_id])
  end

  def edge_params
    params.require(:edge).permit(:source_node_id, :target_node_id)
  end
end
