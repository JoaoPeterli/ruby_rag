# frozen_string_literal: true

class Admin::EvaluationsController < Admin::BaseController
  include Paginatable

  def index
    scope = RagEvalRun.order(created_at: :desc)

    @total_count = scope.count
    @runs = scope.limit(PER_PAGE).offset(page_offset)
  end

  def show
    @run = RagEvalRun.includes(rag_eval_results: :rag_eval_case).find(params[:id])
  end

  def create
    run = Documents::Evaluation::Service.call

    redirect_to admin_evaluation_path(run), notice: "Avaliação ##{run.id} concluída."
  rescue Documents::Evaluation::Service::Error => error
    redirect_to admin_evaluations_path, alert: error.message
  end
end
