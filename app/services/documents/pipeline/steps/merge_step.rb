# frozen_string_literal: true

module Documents
  module Pipeline
    module Steps
      class MergeStep < Step
        def initialize(
          context:,
          multi_query_result_merger: Documents::MultiQueryResultMerger
        )
          super(context:)

          @multi_query_result_merger = multi_query_result_merger
        end

        def call
          started_at = monotonic_time

          query_results = context.queries.each_with_index.map do |query, index|
            {
              query: query,
              query_position: index + 1,
              results: context.hybrid_results.fetch(query, [])
            }
          end

          context.merged_results = multi_query_result_merger.call(
            query_results: query_results,
            limit: context.metadata.fetch(:multi_query_result_limit)
          )

          context.metrics[:merge] = elapsed_ms(started_at)
        end

        private

        attr_reader :multi_query_result_merger
      end
    end
  end
end
