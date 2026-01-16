class WorkflowsController < ApplicationController
  def index
    @workflows = Workflow.includes(:nodes, :edges).all
  end

  def show
    @workflow = Workflow.includes(:nodes, :edges).find(params[:id])
  end

  def new
    @workflow = Workflow.new
  end

  def create
    @workflow = Workflow.new(workflow_params)
    if @workflow.save
      redirect_to @workflow, notice: "Workflow created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @workflow = Workflow.find(params[:id])
  end

  def update
    @workflow = Workflow.find(params[:id])
    if @workflow.update(workflow_params)
      redirect_to @workflow, notice: "Workflow updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @workflow = Workflow.find(params[:id])
    @workflow.destroy
    redirect_to workflows_path, notice: "Workflow deleted."
  end

  # Bulk update node positions from React Flow
  def update_positions
    @workflow = Workflow.find(params[:id])
    nodes_data = params[:nodes] || []

    nodes_data.each do |node_data|
      node = @workflow.nodes.find_by(id: node_data[:id])
      node&.update(
        position_x: node_data[:position][:x],
        position_y: node_data[:position][:y]
      )
    end

    head :ok
  end

  private

  def workflow_params
    params.require(:workflow).permit(:name)
  end
end
