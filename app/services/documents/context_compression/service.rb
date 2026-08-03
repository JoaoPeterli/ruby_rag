# frozen_string_literal: true

module Documents
  module ContextCompression
    class Service
      DEFAULT_STRATEGY =
        Documents::ContextCompression::SimilarityStrategy

      class Error < StandardError; end
      class InvalidChunksError < Error; end
      class InvalidStrategyError < Error; end
      class CompressionError < Error; end

      def self.call(...)
        new(...).call
      end

      def initialize(
        question:,
        chunks:,
        query_embedding:,
        source_chunk_ids: [],
        strategy: DEFAULT_STRATEGY,
        strategy_options: {}
      )
        @question = question
        @chunks = chunks
        @query_embedding = query_embedding
        @source_chunk_ids = source_chunk_ids
        @strategy = strategy
        @strategy_options = strategy_options
      end

      def call
        started_at = monotonic_time

        validate!

        strategy_result =
          strategy.call(
            question: question,
            chunks: chunks,
            query_embedding: query_embedding,
            source_chunk_ids: source_chunk_ids,
            **strategy_options
          )

        compressed_chunks =
          strategy_result.fetch(:chunks)

        removed_chunks =
          chunks.reject do |chunk|
            compressed_chunks.any? do |selected_chunk|
              selected_chunk.id == chunk.id
            end
          end

        Result.new(
          chunks: compressed_chunks,
          removed_chunks: removed_chunks,
          scores: strategy_result.fetch(:scores, {}),
          original_count: chunks.size,
          compressed_count: compressed_chunks.size,
          compression_ratio:
            compression_ratio(
              original_count: chunks.size,
              compressed_count:
                compressed_chunks.size
            ),
          duration_ms: elapsed_ms(started_at),
          strategy: strategy.name
        )
      rescue Error
        raise
      rescue Documents::ContextCompression::Strategy::Error => error
        raise CompressionError,
              "A estratégia de compressão falhou: #{error.message}"
      rescue KeyError => error
        raise CompressionError,
              "Resultado inválido da estratégia: #{error.message}"
      rescue StandardError => error
        raise CompressionError,
              "Falha inesperada na compressão: #{error.message}"
      end

      private

      attr_reader(
        :question,
        :chunks,
        :query_embedding,
        :source_chunk_ids,
        :strategy,
        :strategy_options
      )

      def validate!
        unless chunks.is_a?(Array)
          raise InvalidChunksError,
                "chunks deve ser um array"
        end

        return if strategy.respond_to?(:call)

        raise InvalidStrategyError,
              "strategy deve responder ao método .call"
      end

      def compression_ratio(
        original_count:,
        compressed_count:
      )
        return 0.0 if original_count.zero?

        reduction =
          original_count - compressed_count

        (reduction.to_f / original_count).round(4)
      end

      def monotonic_time
        Process.clock_gettime(
          Process::CLOCK_MONOTONIC
        )
      end

      def elapsed_ms(started_at)
        (
          (
            monotonic_time - started_at
          ) * 1_000
        ).round(2)
      end
    end
  end
end
