# frozen_string_literal: true

module Documents
  module Pipeline
    module Steps
      module Answering
        class PersistStep < Documents::Pipeline::Step
          include LogsStageFailure

          # Roda sempre (cache hit, sem evidência ou sucesso normal) —
          # é por isso que não tem "return if context.result" aqui.
          def call
            return unless context.config.persist_enabled

            rag_query = context.config.persistence_service.call(
              qa_result: context.result,
              retrieval_result: context.retrieval_result,
              account_id: context.account_id
            )

            context.result = context.result.with(
              rag_query_id: rag_query.id,
              rag_answer_id: rag_query.rag_answer&.id
            )
          rescue Documents::RagPersistenceService::Error => error
            log_stage_failure(stage: "persistence", error: error)

            nil
          end
        end
      end
    end
  end
end
