# frozen_string_literal: true

module Api
  module V1
    module Admin
      class DashboardsController < BaseController
        def show
          render json: {
            documents: document_stats,
            queries: query_stats,
            confidence: confidence_stats,
            feedback: feedback_stats,
            cost: cost_stats
          }
        end

        private

        def document_stats
          {
            total: Document.count,
            by_status: Document.group(:status).count,
            total_chunks: DocumentChunk.count
          }
        end

        def query_stats
          total = RagQuery.count
          cache_hits = RagQuery.where(cache_hit: true).count

          {
            total: total,
            cache_hits: cache_hits,
            cache_hit_rate: total.positive? ? (cache_hits.to_f / total).round(4) : nil
          }
        end

        def confidence_stats
          {
            average_score: RagAnswer.average(:confidence_score)&.round(4),
            by_level: RagAnswer.where.not(confidence_level: nil).group(:confidence_level).count,
            refused_count: RagAnswer.where(refused: true).count
          }
        end

        def feedback_stats
          {
            total: RagFeedback.count,
            by_rating: RagFeedback.group(:rating).count
          }
        end

        # Estimativa, não custo real: agrega tokens de todas as
        # respostas e usa o modelo mais frequente. Só fica "priced:
        # true" se o preço desse modelo estiver configurado via ENV
        # (ver Ai::CostCalculator).
        def cost_stats
          prompt_tokens = RagAnswer.sum(:prompt_tokens)
          completion_tokens = RagAnswer.sum(:completion_tokens)
          model = most_common_model

          return { priced: false, prompt_tokens: prompt_tokens, completion_tokens: completion_tokens } unless model

          result = Ai::CostCalculator.call(
            model: model,
            prompt_tokens: prompt_tokens,
            completion_tokens: completion_tokens
          )

          {
            model: model,
            prompt_tokens: prompt_tokens,
            completion_tokens: completion_tokens,
            total_cost_usd: result.total_cost_usd,
            priced: result.priced
          }
        end

        def most_common_model
          RagAnswer
            .where.not(model: nil)
            .group(:model)
            .count
            .max_by { |_model, count| count }
            &.first
        end
      end
    end
  end
end
