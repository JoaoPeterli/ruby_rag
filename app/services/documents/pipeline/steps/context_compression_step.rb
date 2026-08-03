# frozen_string_literal: true

module Documents
  module Pipeline
    module Steps
      class ContextCompressionStep < Step
        include TracksStageFailures

        def initialize(
          context:,
          compression_service:
            Documents::ContextCompression::Service,
          strategy:
            Documents::ContextCompression::SimilarityStrategy,
          logger: Rails.logger
        )
          super(context:)

          @compression_service = compression_service
          @strategy = strategy
          @logger = logger
        end

        def call
          chunks = available_context_chunks

          unless context.metadata[:context_compression_enabled]
            context.compressed_chunks = chunks

            return
          end

          if chunks.blank?
            context.compressed_chunks = []

            return
          end

          query_embedding = resolve_query_embedding

          unless query_embedding
            log_missing_embedding

            context.compressed_chunks = chunks

            return
          end

          compression_result =
            compression_service.call(
              question: context.question,
              chunks: chunks,
              query_embedding: query_embedding,
              source_chunk_ids: source_chunk_ids,
              strategy: strategy,
              strategy_options: {
                max_chunks:
                  context.metadata.fetch(
                    :context_compression_max_chunks
                  ),
                minimum_similarity:
                  context.metadata.fetch(
                    :context_compression_minimum_similarity
                  ),
                preserve_source_chunks:
                  context.metadata.fetch(
                    :context_compression_preserve_source_chunks
                  )
              }
            )

          context.context_compression = compression_result
          context.compressed_chunks = compression_result.chunks

          add_metrics(compression_result)
        rescue Documents::ContextCompression::Service::Error => error
          record_stage_failure(stage: "context_compression", error: error)

          log_failure(error)

          context.compressed_chunks = available_context_chunks
        end

        private

        attr_reader(
          :compression_service,
          :strategy,
          :logger
        )

        def available_context_chunks
          return context.context_chunks if context.context_chunks.present?

          context.results.map(&:chunk)
        end

        def source_chunk_ids
          context.results.map do |result|
            result.chunk.id
          end
        end

        def resolve_query_embedding
          embeddings = context.query_embeddings

          return if embeddings.blank?

          embeddings[context.question] ||
            embeddings[context.search_query] ||
            embeddings.values.first
        end

        def add_metrics(result)
          context.metrics[:context_compression_duration_ms] =
            result.duration_ms

          context.metrics[:context_compression_original_count] =
            result.original_count

          context.metrics[:context_compression_compressed_count] =
            result.compressed_count

          context.metrics[:context_compression_removed_count] =
            result.removed_count

          context.metrics[:context_compression_ratio] =
            result.compression_ratio

          context.metrics[:context_compression_strategy] =
            result.strategy
        end

        def log_missing_embedding
          logger.warn(
            {
              event: "pipeline.context_compression_missing_embedding",
              question: context.question
            }.to_json
          )
        end

        def log_failure(error)
          logger.warn(
            {
              event: "pipeline.context_compression_failure",
              question: context.question,
              error_class: error.class.name,
              error_message: error.message
            }.to_json
          )
        end
      end
    end
  end
end
