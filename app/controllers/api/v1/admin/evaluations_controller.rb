# frozen_string_literal: true

module Api
  module V1
    module Admin
      class EvaluationsController < BaseController
        DEFAULT_LIMIT = 25
        MAX_LIMIT = 100

        def index
          runs = RagEvalRun
            .order(created_at: :desc)
            .limit(limit_param)
            .offset(params[:offset].to_i)

          render json: {
            runs: runs.map { |run| serialize(run) },
            total_count: RagEvalRun.count
          }
        end

        def show
          run = RagEvalRun.includes(rag_eval_results: :rag_eval_case).find(params[:id])

          render json: serialize(run, include_results: true)
        end

        def create
          run = Documents::Evaluation::Service.call

          render json: serialize(run), status: :created
        rescue Documents::Evaluation::Service::Error => error
          render json: { error: error.message }, status: :unprocessable_entity
        end

        private

        def limit_param
          [ params.fetch(:limit, DEFAULT_LIMIT).to_i, MAX_LIMIT ].min.clamp(1, MAX_LIMIT)
        end

        def serialize(run, include_results: false)
          data = {
            id: run.id,
            cases_count: run.cases_count,
            summary: run.summary,
            started_at: run.started_at,
            finished_at: run.finished_at
          }

          if include_results
            data[:results] = run.rag_eval_results.map do |result|
              {
                id: result.id,
                question: result.rag_eval_case.question,
                category: result.rag_eval_case.category,
                errored: result.errored,
                error_message: result.error_message,
                metrics: result.metrics,
                answer: result.answer&.truncate(200)
              }
            end
          end

          data
        end
      end
    end
  end
end
