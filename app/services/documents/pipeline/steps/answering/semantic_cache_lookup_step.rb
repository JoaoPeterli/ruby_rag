# frozen_string_literal: true

module Documents
  module Pipeline
    module Steps
      module Answering
        class SemanticCacheLookupStep < Documents::Pipeline::Step
          include LogsStageFailure

          def call
            context.question_embedding = compute_question_embedding

            return unless context.question_embedding

            hit = context.config.semantic_cache_lookup_service.call(
              question_embedding: context.question_embedding,
              minimum_similarity: context.config.semantic_cache_minimum_similarity,
              scope: cache_scope
            )

            return unless hit

            context.cache_hit = hit
            context.result = Documents::QuestionAnsweringService::ResultBuilder.cache_hit(
              context: context,
              cache_hit: hit
            )
          rescue Documents::SemanticCacheLookupService::Error => error
            log_stage_failure(stage: "semantic_cache_lookup", error: error)

            nil
          end

          private

          def compute_question_embedding
            return unless context.config.semantic_cache_enabled

            embeddings = context.config.embedding_service.call(
              texts: [ context.effective_question ]
            )

            embeddings.is_a?(Array) ? embeddings.first : nil
          rescue Ai::EmbeddingService::Error => error
            log_stage_failure(stage: "semantic_cache_embedding", error: error)

            nil
          end

          def cache_scope
            scope = RagSemanticCacheEntry.not_expired

            return scope if context.account_id.nil?

            scope.where(account_id: context.account_id)
          end
        end
      end
    end
  end
end
