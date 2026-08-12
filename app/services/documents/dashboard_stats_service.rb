# frozen_string_literal: true

module Documents
  # Métricas agregadas do painel admin — usado tanto pelo endpoint JSON
  # (Api::V1::Admin::DashboardsController) quanto pela tela HTML
  # (Admin::DashboardsController), pra não duplicar os cálculos.
  #
  # account: quando informado, escopa tudo pra essa conta -- usado
  # pelo Portal:: (cada cliente só vê os próprios números). Quando
  # nil (padrão), continua agregando globalmente, como o backoffice
  # interno sempre fez.
  class DashboardStatsService
    Result = Data.define(
      :documents,
      :queries,
      :confidence,
      :feedback,
      :cost
    )

    def self.call(account: nil)
      new(account: account).call
    end

    def initialize(account: nil)
      @account = account
    end

    def call
      Result.new(
        documents: document_stats,
        queries: query_stats,
        confidence: confidence_stats,
        feedback: feedback_stats,
        cost: cost_stats
      )
    end

    private

    attr_reader :account

    def document_stats
      scope = scoped(Document)

      {
        total: scope.count,
        by_status: scope.group(:status).count,
        total_chunks: scoped(DocumentChunk).count
      }
    end

    def query_stats
      scope = scoped(RagQuery)
      total = scope.count
      cache_hits = scope.where(cache_hit: true).count

      {
        total: total,
        cache_hits: cache_hits,
        cache_hit_rate: total.positive? ? (cache_hits.to_f / total).round(4) : nil
      }
    end

    def confidence_stats
      scope = scoped_answers

      {
        average_score: scope.average(:confidence_score)&.round(4),
        by_level: scope.where.not(confidence_level: nil).group(:confidence_level).count,
        refused_count: scope.where(refused: true).count
      }
    end

    def feedback_stats
      scope = scoped_feedbacks

      {
        total: scope.count,
        by_rating: scope.group(:rating).count
      }
    end

    # Estimativa, não custo real: agrega tokens de todas as respostas e
    # usa o modelo mais frequente. Só fica "priced: true" se o preço
    # desse modelo estiver configurado via ENV (ver Ai::CostCalculator).
    def cost_stats
      scope = scoped_answers
      prompt_tokens = scope.sum(:prompt_tokens)
      completion_tokens = scope.sum(:completion_tokens)
      model = most_common_model(scope)

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

    def most_common_model(scope)
      scope
        .where.not(model: nil)
        .group(:model)
        .count
        .max_by { |_model, count| count }
        &.first
    end

    def scoped(relation)
      return relation unless account

      relation.where(account_id: account.id)
    end

    # RagAnswer/RagFeedback não têm account_id direto -- precisam
    # passar por RagQuery.
    def scoped_answers
      return RagAnswer.all unless account

      RagAnswer.joins(:rag_query).merge(RagQuery.where(account_id: account.id))
    end

    def scoped_feedbacks
      return RagFeedback.all unless account

      RagFeedback.joins(rag_answer: :rag_query).merge(RagQuery.where(account_id: account.id))
    end
  end
end
