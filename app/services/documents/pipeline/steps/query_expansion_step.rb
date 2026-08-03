# frozen_string_literal: true

module Documents
  module Pipeline
    module Steps
      class QueryExpansionStep < Step
        include TracksStageFailures

        def initialize(
          context:,
          query_expansion_service: Documents::QueryExpansionService
        )
          super(context:)

          @query_expansion_service =
            query_expansion_service
        end

        def call
          return unless context.metadata[:query_expansion_enabled]

          started_at = monotonic_time

          expansion =
            query_expansion_service.call(
              question: context.question
            )

          context.expanded_query = expansion
          context.search_query = expansion.expanded_query

          context.metrics[:query_expansion] = elapsed_ms(started_at)
        rescue Documents::QueryExpansionService::Error => error
          record_stage_failure(stage: "query_expansion", error: error)

          context.search_query = context.question
        end

        private

        attr_reader :query_expansion_service
      end
    end
  end
end
