# frozen_string_literal: true

require "set"

module Documents
  module ContextCompression
    class SimilarityStrategy < Strategy
      DEFAULT_MAX_CHUNKS = 8
      DEFAULT_MINIMUM_SIMILARITY = 0.30
      DEFAULT_PRESERVE_SOURCE_CHUNKS = true

      class InvalidMaxChunksError < Error; end
      class InvalidMinimumSimilarityError < Error; end

      def initialize(
        question:,
        chunks:,
        query_embedding:,
        source_chunk_ids: [],
        max_chunks: DEFAULT_MAX_CHUNKS,
        minimum_similarity: DEFAULT_MINIMUM_SIMILARITY,
        preserve_source_chunks:
          DEFAULT_PRESERVE_SOURCE_CHUNKS
      )
        super(
          question: question,
          chunks: chunks,
          query_embedding: query_embedding
        )

        @source_chunk_ids =
          source_chunk_ids.to_set

        @max_chunks = max_chunks
        @minimum_similarity = minimum_similarity
        @preserve_source_chunks =
          preserve_source_chunks
      end

      def call
        validate!
        validate_configuration!

        scored_chunks = score_chunks
        selected_chunks = select_chunks(scored_chunks)

        {
          chunks: order_chunks(selected_chunks),
          scores: build_scores(scored_chunks)
        }
      end

      private

      attr_reader(
        :source_chunk_ids,
        :max_chunks,
        :minimum_similarity,
        :preserve_source_chunks
      )

      def validate_configuration!
        validate_max_chunks!
        validate_minimum_similarity!
      end

      def validate_max_chunks!
        return if max_chunks.is_a?(Integer) &&
                  max_chunks.positive?

        raise InvalidMaxChunksError,
              "max_chunks deve ser um inteiro maior que zero"
      end

      def validate_minimum_similarity!
        valid =
          minimum_similarity.is_a?(Numeric) &&
          minimum_similarity.between?(-1.0, 1.0)

        return if valid

        raise InvalidMinimumSimilarityError,
              "minimum_similarity deve estar entre -1 e 1"
      end

      def score_chunks
        chunks.filter_map do |chunk|
          chunk_embedding =
            normalize_embedding(chunk.embedding)

          next if chunk_embedding.empty?

          similarity =
            cosine_similarity(
              normalized_query_embedding,
              chunk_embedding
            )

          ScoredChunk.new(
            chunk: chunk,
            similarity: similarity,
            source: source_chunk_ids.include?(chunk.id)
          )
        end
      end

      def select_chunks(scored_chunks)
        source_chunks =
          scored_chunks.select(&:source)

        relevant_chunks =
          scored_chunks.select do |item|
            item.similarity >= minimum_similarity
          end

        candidates =
          if preserve_source_chunks
            (source_chunks + relevant_chunks)
              .uniq { |item| item.chunk.id }
          else
            relevant_chunks
          end

        prioritized =
          candidates.sort_by do |item|
            [
              item.source ? 0 : 1,
              -item.similarity,
              item.chunk.document_id,
              item.chunk.position
            ]
          end

        effective_max_chunks =
          if preserve_source_chunks
            [
              max_chunks,
              source_chunks.size
            ].max
          else
            max_chunks
          end

        selected = prioritized.first(effective_max_chunks)

        ensure_at_least_one_chunk(
          selected,
          scored_chunks
        )
      end

      def ensure_at_least_one_chunk(
        selected,
        scored_chunks
      )
        return selected if selected.any?
        return [] if scored_chunks.empty?

        [
          scored_chunks.max_by(&:similarity)
        ]
      end

      def order_chunks(scored_chunks)
        scored_chunks
          .map(&:chunk)
          .sort_by do |chunk|
            [
              chunk.document_id,
              chunk.position
            ]
          end
      end

      def build_scores(scored_chunks)
        scored_chunks.each_with_object({}) do |item, hash|
          hash[item.chunk.id] = {
            similarity: item.similarity.round(6),
            source: item.source
          }
        end
      end

      def normalized_query_embedding
        @normalized_query_embedding ||=
          normalize_embedding(query_embedding)
      end

      def normalize_embedding(value)
        array =
          if value.respond_to?(:to_a)
            value.to_a
          else
            Array(value)
          end

        array.map(&:to_f)
      end

      def cosine_similarity(vector_a, vector_b)
        return 0.0 if vector_a.empty?
        return 0.0 if vector_b.empty?
        return 0.0 unless vector_a.length == vector_b.length

        dot_product = 0.0
        norm_a = 0.0
        norm_b = 0.0

        vector_a.each_index do |index|
          value_a = vector_a[index]
          value_b = vector_b[index]

          dot_product += value_a * value_b
          norm_a += value_a * value_a
          norm_b += value_b * value_b
        end

        denominator =
          Math.sqrt(norm_a) * Math.sqrt(norm_b)

        return 0.0 if denominator.zero?

        dot_product / denominator
      end
    end
  end
end
