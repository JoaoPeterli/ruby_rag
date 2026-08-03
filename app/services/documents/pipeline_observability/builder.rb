# frozen_string_literal: true

module Documents
  module PipelineObservability
    class Builder
      def self.call(...)
        new(...).call
      end

      # qa_result é opcional: só o retrieval já dá stage_metrics,
      # stage_failures e candidate_counts. token_usage/cost dependem da
      # geração final da resposta (QuestionAnsweringService::Result).
      def initialize(
        retrieval_result:,
        qa_result: nil,
        cost_calculator: Ai::CostCalculator
      )
        @retrieval_result = retrieval_result
        @qa_result = qa_result
        @cost_calculator = cost_calculator
      end

      def call
        Report.new(
          stage_metrics: retrieval_result.metrics,
          stage_failures: retrieval_result.stage_failures,
          candidate_counts: candidate_counts,
          token_usage: token_usage,
          cost: cost,
          retrieval_duration_ms: retrieval_result.duration_ms,
          total_duration_ms: qa_result&.duration_ms || retrieval_result.duration_ms
        )
      end

      private

      attr_reader :retrieval_result, :qa_result, :cost_calculator

      def candidate_counts
        {
          results: retrieval_result.results.size,
          context_chunks: retrieval_result.context_chunks.size,
          compressed_chunks: retrieval_result.compressed_chunks.size,
          cross_encoder_results: retrieval_result.cross_encoder_results.size
        }
      end

      def token_usage
        return unless qa_result

        {
          prompt_tokens: qa_result.prompt_tokens,
          completion_tokens: qa_result.completion_tokens,
          total_tokens: qa_result.total_tokens
        }
      end

      def cost
        return unless qa_result

        cost_calculator.call(
          model: qa_result.model,
          prompt_tokens: qa_result.prompt_tokens,
          completion_tokens: qa_result.completion_tokens
        )
      end
    end
  end
end
