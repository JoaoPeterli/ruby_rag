# frozen_string_literal: true

module Documents
  module Pipeline
    module Steps
      class EmbeddingStep < Step
        def initialize(
          context:,
          embedding_service: Ai::EmbeddingService
        )
          super(context:)

          @embedding_service = embedding_service
        end

        def call
          started_at = monotonic_time

          embeddings = embedding_service.call(texts: context.queries)

          context.query_embeddings = context.queries.zip(embeddings).to_h

          context.metrics[:embedding] = elapsed_ms(started_at)
        end

        private

        attr_reader :embedding_service
      end
    end
  end
end
