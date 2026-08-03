# frozen_string_literal: true

module Documents
  module Pipeline
    module Steps
      module Answering
        class StoreCacheStep < Documents::Pipeline::Step
          include LogsStageFailure

          # Roda mesmo quando context.result já foi definido por outro
          # step (ex.: resposta "sem evidência" também é cacheada, pra
          # perguntas parecidas não repetirem o retrieval caro à toa) —
          # só pula quando o resultado É um cache hit, pra não regravar
          # o que acabou de ser lido do cache.
          def call
            return if context.cache_hit
            return unless context.config.semantic_cache_enabled && context.question_embedding

            context.config.semantic_cache_store_service.call(
              question: context.effective_question,
              question_embedding: context.question_embedding,
              qa_result: context.result,
              ttl: context.config.semantic_cache_ttl,
              account_id: context.account_id
            )
          rescue Documents::SemanticCacheStoreService::Error => error
            log_stage_failure(stage: "semantic_cache_store", error: error)

            nil
          end
        end
      end
    end
  end
end
