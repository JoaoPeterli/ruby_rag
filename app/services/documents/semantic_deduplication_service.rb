# frozen_string_literal: true

module Documents
  # Aponta candidatos a duplicata via similaridade de embedding — não
  # deleta nada automaticamente. Threshold alto (0.98) porque isso
  # precisa ser "praticamente idêntico", não apenas "sobre o mesmo
  # assunto" (esse caso já é tratado pelo MMR no retrieval).
  class SemanticDeduplicationService
    DEFAULT_MINIMUM_SIMILARITY = 0.98
    DEFAULT_LIMIT = 5

    Candidate = Data.define(:chunk, :similarity)
    Result = Data.define(:chunk, :duplicates, :duplicate_count)

    class Error < StandardError; end
    class InvalidChunkError < Error; end

    def self.call(...)
      new(...).call
    end

    def initialize(
      chunk:,
      minimum_similarity: DEFAULT_MINIMUM_SIMILARITY,
      limit: DEFAULT_LIMIT,
      scope: DocumentChunk.all
    )
      @chunk = chunk
      @minimum_similarity = minimum_similarity
      @limit = limit
      @scope = scope
    end

    def call
      validate!

      duplicates = find_duplicates

      Result.new(
        chunk: chunk,
        duplicates: duplicates,
        duplicate_count: duplicates.size
      )
    rescue Error
      raise
    rescue StandardError => error
      raise Error, "Falha ao buscar duplicatas semânticas: #{error.message}"
    end

    private

    attr_reader :chunk, :minimum_similarity, :limit, :scope

    def validate!
      valid =
        chunk.is_a?(DocumentChunk) &&
        chunk.persisted? &&
        valid_embedding?(chunk.embedding)

      return if valid

      raise InvalidChunkError,
            "chunk deve ser um DocumentChunk persistido com embedding válido"
    end

    def valid_embedding?(embedding)
      embedding.is_a?(Array) &&
        embedding.any? &&
        embedding.all? { |value| value.is_a?(Numeric) }
    end

    def find_duplicates
      scope
        .where.not(id: chunk.id)
        .nearest_neighbors(:embedding, chunk.embedding, distance: "cosine")
        .first(limit)
        .filter_map do |candidate|
          similarity = calculate_similarity(candidate)

          next if similarity < minimum_similarity

          Candidate.new(chunk: candidate, similarity: similarity)
        end
    end

    def calculate_similarity(candidate)
      (1.0 - candidate.neighbor_distance.to_f).clamp(0.0, 1.0)
    end
  end
end
