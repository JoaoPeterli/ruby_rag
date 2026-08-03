# frozen_string_literal: true

module Documents
  module Pipeline
    module Steps
      class MmrStep < Step
        def initialize(
          context:,
          mmr_service: Documents::MmrService
        )
          super(context:)

          @mmr_service = mmr_service
        end

        def call
          started_at = monotonic_time

          context.results = mmr_service.call(
            results: input_results,
            limit: context.metadata.fetch(:search_limit),
            lambda_value: context.metadata.fetch(:mmr_lambda)
          )

          context.metrics[:mmr] = elapsed_ms(started_at)
        end

        private

        attr_reader :mmr_service

        def input_results
          return context.cross_encoder_results if context.cross_encoder_results.present?
          return context.reranked_results if context.reranked_results.present?

          context.merged_results
        end
      end
    end
  end
end
