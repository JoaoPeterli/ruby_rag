# frozen_string_literal: true

module Documents
  module Pipeline
    module Steps
      class RerankStep < Step
        def initialize(
          context:,
          reranking_service: Documents::RerankingService
        )
          super(context:)

          @reranking_service = reranking_service
        end

        def call
          started_at = monotonic_time

          context.reranked_results = reranking_service.call(
            question: context.question,
            search_results: context.merged_results,
            limit: context.metadata.fetch(:candidate_limit)
          )

          context.metrics[:rerank] = elapsed_ms(started_at)
        end

        private

        attr_reader :reranking_service
      end
    end
  end
end
