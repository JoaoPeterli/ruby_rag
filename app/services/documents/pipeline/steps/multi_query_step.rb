# frozen_string_literal: true

module Documents
  module Pipeline
    module Steps
      class MultiQueryStep < Step
        include TracksStageFailures

        def initialize(
          context:,
          multi_query_service: Documents::MultiQueryService
        )
          super(context:)

          @multi_query_service =
            multi_query_service
        end

        def call
          started_at = monotonic_time

          multi_query = generate

          context.queries = build_queries(multi_query)
          context.metadata[:multi_query] = multi_query

          context.metrics[:multi_query] = elapsed_ms(started_at)
        end

        private

        attr_reader :multi_query_service

        def generate
          return unless context.metadata[:multi_query_enabled]

          multi_query_service.call(
            question: context.search_query,
            query_count: context.metadata.fetch(:multi_query_count)
          )
        rescue Documents::MultiQueryService::Error => error
          record_stage_failure(stage: "multi_query", error: error)

          nil
        end

        def build_queries(multi_query)
          queries =
            if multi_query
              [
                context.question,
                context.search_query,
                *multi_query.queries
              ]
            else
              [
                context.question,
                context.search_query
              ]
            end

          queries
            .map(&:to_s)
            .map(&:strip)
            .reject(&:blank?)
            .uniq { |query| normalize_query(query) }
        end

        def normalize_query(query)
          query
            .unicode_normalize(:nfkd)
            .encode(
              "ASCII",
              invalid: :replace,
              undef: :replace,
              replace: ""
            )
            .downcase
            .gsub(/[^\p{Alnum}\s]/, " ")
            .squeeze(" ")
            .strip
        end
      end
    end
  end
end
