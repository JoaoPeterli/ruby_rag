# frozen_string_literal: true

module Documents
  module Pipeline
    module Steps
      class MetadataExtractionStep < Step
        include TracksStageFailures

        def initialize(
          context:,
          metadata_extraction_service:
            Documents::MetadataExtractionService,
          logger: Rails.logger
        )
          super(context:)

          @metadata_extraction_service =
            metadata_extraction_service
          @logger = logger
        end

        def call
          unless context.metadata[:metadata_extraction_enabled]
            context.metadata_filters = Documents::MetadataFilters.empty

            return
          end

          started_at = monotonic_time

          extraction =
            metadata_extraction_service.call(
              question: context.question
            )

          context.metadata_extraction = extraction
          context.metadata_filters = extraction.filters

          context.metrics[:metadata_extraction] = elapsed_ms(started_at)
        rescue Documents::MetadataExtractionService::Error => error
          record_stage_failure(stage: "metadata_extraction", error: error)

          logger.warn(
            {
              event: "pipeline.metadata_extraction_failure",
              question: context.question,
              error_class: error.class.name,
              error_message: error.message
            }.to_json
          )

          context.metadata_filters = Documents::MetadataFilters.empty
        end

        private

        attr_reader(
          :metadata_extraction_service,
          :logger
        )
      end
    end
  end
end
