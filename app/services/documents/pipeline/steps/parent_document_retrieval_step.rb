# frozen_string_literal: true

module Documents
  module Pipeline
    module Steps
      class ParentDocumentRetrievalStep < Step
        include TracksStageFailures

        def initialize(
          context:,
          parent_retrieval_service:
            Documents::ParentDocumentRetrievalService,
          logger: Rails.logger
        )
          super(context:)

          @parent_retrieval_service = parent_retrieval_service
          @logger = logger
        end

        def call
          unless context.metadata[:parent_retrieval_enabled]
            context.context_chunks = context.results.map(&:chunk)

            return
          end

          if context.results.blank?
            context.context_chunks = []

            return
          end

          started_at = monotonic_time

          parent_result =
            parent_retrieval_service.call(
              results: context.results,
              window_size: context.metadata.fetch(:parent_retrieval_window_size),
              max_chunks: context.metadata.fetch(:parent_retrieval_max_chunks)
            )

          context.parent_retrieval = parent_result
          context.context_chunks = parent_result.chunks

          context.metrics[:parent_retrieval] = elapsed_ms(started_at)
        rescue Documents::ParentDocumentRetrievalService::Error => error
          record_stage_failure(stage: "parent_retrieval", error: error)

          logger.warn(
            {
              event: "pipeline.parent_retrieval_failure",
              question: context.question,
              error_class: error.class.name,
              error_message: error.message
            }.to_json
          )

          context.context_chunks = context.results.map(&:chunk)
        end

        private

        attr_reader(
          :parent_retrieval_service,
          :logger
        )
      end
    end
  end
end
