# frozen_string_literal: true

module Documents
  class QuestionAnsweringService
    # Centraliza a montagem do Result (e do Source aninhado) pros três
    # desfechos possíveis do pipeline de resposta: sucesso normal,
    # "sem evidência" e cache hit. Fica como classe irmã dos Data.define
    # que monta (Result/Source/NO_EVIDENCE_ANSWER, visíveis por
    # escopo léxico por estar aninhada em QuestionAnsweringService).
    class ResultBuilder
      class << self
        def success(
          context:,
          chat_result:,
          retrieval_result:,
          citation_result:,
          groundedness_result:,
          hallucination_result:,
          confidence_result:
        )
          Result.new(
            question: context.normalized_question,
            effective_question: context.effective_question,
            answer: chat_result.content,
            sources: build_sources(
              retrieval_result.results,
              parent_retrieval: retrieval_result.parent_retrieval,
              citation_result: citation_result
            ),
            search_query: retrieval_result.search_query,
            model: chat_result.model,
            finish_reason: chat_result.finish_reason,
            usage: chat_result.usage,
            prompt_tokens: chat_result.prompt_tokens,
            completion_tokens: chat_result.completion_tokens,
            total_tokens: chat_result.total_tokens,
            citations: citation_result&.citations || [],
            citation_coverage: citation_result&.citation_coverage,
            grounded: groundedness_result&.grounded,
            refused: groundedness_result&.refused,
            hallucination_check: hallucination_result,
            confidence_score: confidence_result&.score,
            confidence_level: confidence_result&.level,
            cache_hit: false,
            cache_similarity: nil,
            query_expansion_duration_ms:
              retrieval_result.query_expansion&.duration_ms,
            retrieval_duration_ms: retrieval_result.duration_ms,
            duration_ms: elapsed_milliseconds(context.started_at),
            rag_query_id: nil,
            rag_answer_id: nil
          )
        end

        def no_evidence(context:, error:)
          Result.new(
            question: context.normalized_question,
            effective_question: context.effective_question,
            answer: NO_EVIDENCE_ANSWER,
            sources: [],
            search_query: error.search_query,
            model: nil,
            finish_reason: nil,
            usage: nil,
            prompt_tokens: nil,
            completion_tokens: nil,
            total_tokens: nil,
            citations: [],
            citation_coverage: nil,
            grounded: true,
            refused: true,
            hallucination_check: nil,
            confidence_score: nil,
            confidence_level: nil,
            cache_hit: false,
            cache_similarity: nil,
            query_expansion_duration_ms: nil,
            retrieval_duration_ms: error.duration_ms,
            duration_ms: elapsed_milliseconds(context.started_at),
            rag_query_id: nil,
            rag_answer_id: nil
          )
        end

        def cache_hit(context:, cache_hit:)
          entry = cache_hit.entry

          Result.new(
            question: context.normalized_question,
            effective_question: context.effective_question,
            answer: entry.answer,
            sources: [],
            search_query: nil,
            model: entry.model,
            finish_reason: nil,
            usage: nil,
            prompt_tokens: nil,
            completion_tokens: nil,
            total_tokens: nil,
            citations: [],
            citation_coverage: nil,
            grounded: nil,
            refused: nil,
            hallucination_check: nil,
            confidence_score: entry.confidence_score,
            confidence_level: entry.confidence_level,
            cache_hit: true,
            cache_similarity: cache_hit.similarity,
            query_expansion_duration_ms: nil,
            retrieval_duration_ms: nil,
            duration_ms: elapsed_milliseconds(context.started_at),
            rag_query_id: nil,
            rag_answer_id: nil
          )
        end

        private

        def build_sources(search_results, parent_retrieval:, citation_result:)
          cited_chunk_ids = citation_result&.cited_chunk_ids

          search_results.map do |search_result|
            chunk = search_result.chunk

            Source.new(
              chunk_id: chunk.id,
              document_id: extract_document_id(chunk),
              content: chunk.content,
              position: search_result.position,
              original_position: search_result.original_position,
              vector_position: search_result.vector_position,
              text_position: search_result.text_position,
              distance: search_result.distance,
              similarity: search_result.similarity,
              text_score: search_result.text_score,
              normalized_text_score: search_result.normalized_text_score,
              hybrid_score: search_result.hybrid_score,
              multi_query_score: search_result.multi_query_score,
              matched_queries: search_result.matched_queries,
              query_match_count: search_result.query_match_count,
              best_query_position: search_result.best_query_position,
              rerank_score: search_result.rerank_score,
              lexical_score: search_result.lexical_score,
              matched_terms: search_result.matched_terms,
              cross_encoder_score: search_result.cross_encoder_score,
              cross_encoder_reason: search_result.cross_encoder_reason,
              combined_score: search_result.combined_score,
              mmr_score: search_result.mmr_score,
              redundancy_score: search_result.redundancy_score,
              context_chunk_ids: context_chunk_ids_for(
                chunk,
                parent_retrieval
              ),
              cited: cited_chunk_ids&.include?(chunk.id)
            )
          end
        end

        def context_chunk_ids_for(source_chunk, parent_retrieval)
          return [ source_chunk.id ] unless parent_retrieval

          group =
            parent_retrieval.groups.find do |item|
              item.document_id == source_chunk.document_id &&
                item.source_chunk_ids.include?(source_chunk.id)
            end

          group ? group.chunks.map(&:id) : [ source_chunk.id ]
        end

        def extract_document_id(chunk)
          return chunk.document_id if chunk.respond_to?(:document_id)
          return chunk.document.id if chunk.respond_to?(:document)

          nil
        end

        def elapsed_milliseconds(started_at)
          return 0 unless started_at

          finished_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          ((finished_at - started_at) * 1_000).round
        end
      end
    end
  end
end
