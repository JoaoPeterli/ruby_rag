# frozen_string_literal: true

module Api
  module V1
    module Admin
      class QueriesController < BaseController
        DEFAULT_LIMIT = 25
        MAX_LIMIT = 100

        def index
          queries = RagQuery
            .includes(:rag_answer)
            .order(created_at: :desc)
            .limit(limit_param)
            .offset(params[:offset].to_i)

          render json: {
            queries: queries.map { |query| serialize(query) },
            total_count: RagQuery.count
          }
        end

        def show
          query = RagQuery.includes(:rag_answer, rag_retrieval_results: :document_chunk).find(params[:id])

          render json: serialize(query, include_details: true)
        end

        private

        def limit_param
          [ params.fetch(:limit, DEFAULT_LIMIT).to_i, MAX_LIMIT ].min.clamp(1, MAX_LIMIT)
        end

        def serialize(query, include_details: false)
          answer = query.rag_answer

          data = {
            id: query.id,
            question: query.question,
            search_query: query.search_query,
            status: query.status,
            cache_hit: query.cache_hit,
            duration_ms: query.duration_ms,
            total_tokens: query.total_tokens,
            created_at: query.created_at,
            answer: answer && {
              id: answer.id,
              answer: include_details ? answer.answer : answer.answer.to_s.truncate(200),
              model: answer.model,
              grounded: answer.grounded,
              refused: answer.refused,
              citation_coverage: answer.citation_coverage,
              confidence_score: answer.confidence_score,
              confidence_level: answer.confidence_level
            }
          }

          if include_details
            data[:metrics] = query.metrics
            data[:retrieval_results] = query.rag_retrieval_results.map do |result|
              {
                document_chunk_id: result.document_chunk_id,
                position: result.position,
                cited: result.cited,
                hybrid_score: result.hybrid_score,
                rerank_score: result.rerank_score,
                combined_score: result.combined_score,
                mmr_score: result.mmr_score
              }
            end
          end

          data
        end
      end
    end
  end
end
