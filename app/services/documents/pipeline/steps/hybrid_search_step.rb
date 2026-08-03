# frozen_string_literal: true

module Documents
  module Pipeline
    module Steps
      class HybridSearchStep < Step
        def initialize(
          context:,
          vector_search_service: Documents::VectorSearchService,
          full_text_search_service: Documents::FullTextSearchService,
          hybrid_search_service: Documents::HybridSearchService,
          account_scope_builder: Documents::AccountScopeBuilder,
          logger: Rails.logger
        )
          super(context:)

          @vector_search_service = vector_search_service
          @full_text_search_service = full_text_search_service
          @hybrid_search_service = hybrid_search_service
          @account_scope_builder = account_scope_builder
          @logger = logger
        end

        def call
          started_at = monotonic_time

          perform_searches

          unless any_results? || context.metadata_filters.empty?
            logger.warn(
              {
                event: "pipeline.metadata_filter_fallback",
                filters: context.metadata_filters.to_h
              }.to_json
            )

            context.metadata[:stage_failures] ||= []
            context.metadata[:stage_failures] << {
              stage: "hybrid_search",
              error_class: "MetadataFilterFallback",
              error_message: "Nenhum resultado com os filtros #{context.metadata_filters.to_h}; buscou novamente sem filtros"
            }

            context.metadata_filters = Documents::MetadataFilters.empty

            clear_search_results
            perform_searches
          end

          context.metrics[:hybrid_search] = elapsed_ms(started_at)
        end

        private

        attr_reader(
          :vector_search_service,
          :full_text_search_service,
          :hybrid_search_service,
          :account_scope_builder,
          :logger
        )

        def perform_searches
          candidate_limit = context.metadata.fetch(:candidate_limit)
          minimum_similarity = context.metadata.fetch(:minimum_similarity)
          scope = account_scope

          context.query_embeddings.each do |query, embedding|
            vector_results = vector_search_service.call(
              query: query,
              query_embedding: embedding,
              limit: candidate_limit,
              candidate_limit: candidate_limit,
              minimum_similarity: minimum_similarity,
              filters: context.metadata_filters,
              relation: scope
            )

            text_results = full_text_search_service.call(
              query: query,
              limit: candidate_limit,
              filters: context.metadata_filters,
              scope: scope
            )

            context.vector_results[query] = vector_results
            context.text_results[query] = text_results

            context.hybrid_results[query] = hybrid_search_service.call(
              vector_results: vector_results,
              text_results: text_results,
              limit: candidate_limit
            )
          end
        end

        def account_scope
          account_scope_builder.call(account_id: context.metadata[:account_id])
        end

        def any_results?
          context.hybrid_results.values.any?(&:any?)
        end

        def clear_search_results
          context.vector_results = {}
          context.text_results = {}
          context.hybrid_results = {}
        end
      end
    end
  end
end
