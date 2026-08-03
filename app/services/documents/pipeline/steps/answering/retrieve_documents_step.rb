# frozen_string_literal: true

module Documents
  module Pipeline
    module Steps
      module Answering
        class RetrieveDocumentsStep < Documents::Pipeline::Step
          def call
            return if context.result

            context.retrieval_result = context.config.retrieval_pipeline.call(
              question: context.effective_question,
              account_id: context.account_id,
              search_limit: context.config.search_limit,
              candidate_limit: context.config.candidate_limit,
              minimum_similarity: context.config.minimum_similarity,
              mmr_lambda: context.config.mmr_lambda,
              **pipeline_overrides
            )
          rescue Documents::RetrievalPipelineService::NoRelevantResultsError => error
            context.result = Documents::QuestionAnsweringService::ResultBuilder.no_evidence(
              context: context,
              error: error
            )
          rescue Documents::RetrievalPipelineService::Error => error
            raise Documents::QuestionAnsweringService::RetrievalError,
                  "Não foi possível recuperar o contexto: #{error.message}"
          end

          private

          def pipeline_overrides
            plan = context.adaptive_plan
            config = context.config

            {
              query_expansion_enabled:
                config.query_expansion_enabled.nil? ? plan&.query_expansion_enabled : config.query_expansion_enabled,
              multi_query_enabled:
                config.multi_query_enabled.nil? ? plan&.multi_query_enabled : config.multi_query_enabled,
              metadata_extraction_enabled:
                config.metadata_extraction_enabled.nil? ? plan&.metadata_extraction_enabled : config.metadata_extraction_enabled,
              cross_encoder_enabled:
                config.cross_encoder_enabled.nil? ? plan&.cross_encoder_enabled : config.cross_encoder_enabled,
              parent_retrieval_enabled:
                config.parent_retrieval_enabled.nil? ? plan&.parent_retrieval_enabled : config.parent_retrieval_enabled,
              context_compression_enabled:
                config.context_compression_enabled.nil? ? plan&.context_compression_enabled : config.context_compression_enabled
            }.compact
          end
        end
      end
    end
  end
end
