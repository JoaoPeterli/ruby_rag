# frozen_string_literal: true

module Documents
  module Pipeline
    module Steps
      module Answering
        class BuildContextStep < Documents::Pipeline::Step
          def call
            return if context.result

            chunks = context_chunks_for(context.retrieval_result)

            results = to_vector_search_results(
              chunks: chunks,
              search_results: context.retrieval_result.results
            )

            budget = context.token_budget

            context.context_result =
              if budget
                context.config.context_builder.call(
                  results: results,
                  max_characters: budget.context_budget_characters
                )
              else
                context.config.context_builder.call(results: results)
              end
          rescue Documents::ContextBuilder::Error => error
            raise Documents::QuestionAnsweringService::ContextBuildError,
                  "Não foi possível construir o contexto: #{error.message}"
          end

          private

          def context_chunks_for(retrieval_result)
            if retrieval_result.compressed_chunks.present?
              retrieval_result.compressed_chunks
            elsif retrieval_result.context_chunks.present?
              retrieval_result.context_chunks
            else
              retrieval_result.results.map(&:chunk)
            end
          end

          def to_vector_search_results(chunks:, search_results:)
            search_results_by_chunk_id =
              search_results.index_by { |search_result| search_result.chunk.id }

            chunks.map do |chunk|
              search_result = search_results_by_chunk_id[chunk.id]

              Documents::VectorSearchResult.new(
                chunk_id: chunk.id,
                document_id: chunk.document_id,
                content: chunk.content,
                position: chunk.position,
                distance: search_result&.distance,
                score: search_result&.similarity || 0.0,
                metadata: chunk.metadata.to_h
              )
            end
          end
        end
      end
    end
  end
end
