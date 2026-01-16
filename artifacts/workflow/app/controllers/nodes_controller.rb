class NodesController < ApplicationController
  before_action :set_workflow

  def create
    @node = @workflow.nodes.build(node_params)
    if @node.save
      render json: @node
    else
      render json: { errors: @node.errors }, status: :unprocessable_entity
    end
  end

  def update
    @node = @workflow.nodes.find(params[:id])
    if @node.update(node_params)
      render json: @node
    else
      render json: { errors: @node.errors }, status: :unprocessable_entity
    end
  end

  def destroy
    @node = @workflow.nodes.find(params[:id])
    @node.destroy
    head :ok
  end

  private

  def set_workflow
    @workflow = Workflow.find(params[:workflow_id])
  end

  def node_params
    params.require(:node).permit(:label, :node_type, :position_x, :position_y)
  end
end
