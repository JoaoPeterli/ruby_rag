# frozen_string_literal: true

require "set"

module Documents
  class ParentDocumentRetrievalService
    DEFAULT_WINDOW_SIZE = 2
    DEFAULT_MAX_CHUNKS = 20

    Result = Data.define(
      :chunks,
      :groups,
      :source_chunk_ids,
      :duration_ms
    )

    Group = Data.define(
      :document_id,
      :source_chunk_ids,
      :chunks,
      :minimum_position,
      :maximum_position
    )

    class Error < StandardError; end
    class InvalidResultsError < Error; end
    class InvalidWindowSizeError < Error; end
    class InvalidMaxChunksError < Error; end
    class RetrievalError < Error; end

    def self.call(...)
      new(...).call
    end

    def initialize(
      results:,
      window_size: DEFAULT_WINDOW_SIZE,
      max_chunks: DEFAULT_MAX_CHUNKS,
      chunk_scope: DocumentChunk.all
    )
      @results = results
      @window_size = window_size
      @max_chunks = max_chunks
      @chunk_scope = chunk_scope
    end

    def call
      started_at = monotonic_time

      validate!

      source_chunks = extract_source_chunks
      groups = retrieve_groups(source_chunks)
      chunks = build_final_chunks(groups, source_chunks)

      Result.new(
        chunks: chunks,
        groups: groups,
        source_chunk_ids: source_chunks.map(&:id),
        duration_ms: elapsed_ms(started_at)
      )
    rescue Error
      raise
    rescue ActiveRecord::ActiveRecordError => error
      raise RetrievalError,
            "Não foi possível recuperar os chunks relacionados: #{error.message}"
    rescue StandardError => error
      raise Error,
            "Falha inesperada no Parent Retrieval: #{error.message}"
    end

    private

    attr_reader(
      :results,
      :window_size,
      :max_chunks,
      :chunk_scope
    )

    def validate!
      validate_results!
      validate_window_size!
      validate_max_chunks!
    end

    def validate_results!
      valid =
        results.is_a?(Array) &&
        results.all? do |result|
          result.respond_to?(:chunk) &&
            result.chunk.is_a?(DocumentChunk)
        end

      return if valid

      raise InvalidResultsError,
            "results deve ser um array de resultados contendo chunks"
    end

    def validate_window_size!
      valid =
        window_size.is_a?(Integer) &&
        window_size >= 0

      return if valid

      raise InvalidWindowSizeError,
            "window_size deve ser um inteiro maior ou igual a zero"
    end

    def validate_max_chunks!
      valid =
        max_chunks.is_a?(Integer) &&
        max_chunks.positive?

      return if valid

      raise InvalidMaxChunksError,
            "max_chunks deve ser um inteiro maior que zero"
    end

    def extract_source_chunks
      results
        .map(&:chunk)
        .uniq(&:id)
    end

    def retrieve_groups(source_chunks)
      source_chunks
        .group_by(&:document_id)
        .map do |document_id, document_source_chunks|
          retrieve_group(
            document_id: document_id,
            source_chunks: document_source_chunks
          )
        end
    end

    def retrieve_group(document_id:, source_chunks:)
      positions = source_chunks.map(&:position)

      minimum_position =
        [ positions.min - window_size, 0 ].max

      maximum_position =
        positions.max + window_size

      related_chunks =
        chunk_scope
          .where(document_id: document_id)
          .where(
            position: minimum_position..maximum_position
          )
          .order(:position)
          .to_a

      Group.new(
        document_id: document_id,
        source_chunk_ids: source_chunks.map(&:id),
        chunks: related_chunks,
        minimum_position: minimum_position,
        maximum_position: maximum_position
      )
    end

    def build_final_chunks(groups, source_chunks)
      source_chunk_ids = source_chunks.map(&:id).to_set

      all_chunks =
        groups
          .flat_map(&:chunks)
          .uniq(&:id)

      prioritized =
        all_chunks.sort_by do |chunk|
          [
            source_chunk_ids.include?(chunk.id) ? 0 : 1,
            source_result_position(chunk.id),
            distance_from_nearest_source(
              chunk,
              source_chunks
            ),
            chunk.document_id,
            chunk.position
          ]
        end

      selected_chunks =
        prioritized
          .first(max_chunks)
          .sort_by do |chunk|
            [
              chunk.document_id,
              chunk.position
            ]
          end

      selected_chunks
    end

    def source_result_position(chunk_id)
      index =
        results.index do |result|
          result.chunk.id == chunk_id
        end

      index || results.size
    end

    def distance_from_nearest_source(chunk, source_chunks)
      document_source_chunks =
        source_chunks.select do |source_chunk|
          source_chunk.document_id == chunk.document_id
        end

      document_source_chunks
        .map do |source_chunk|
          (source_chunk.position - chunk.position).abs
        end
        .min || Float::INFINITY
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def elapsed_ms(started_at)
      ((monotonic_time - started_at) * 1_000).round(2)
    end
  end
end
