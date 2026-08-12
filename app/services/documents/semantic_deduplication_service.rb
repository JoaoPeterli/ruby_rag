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
      scope: DocumentChunk.all,
      vector_store: Ai::VectorStoreService.default
    )
      @chunk = chunk
      @minimum_similarity = minimum_similarity
      @limit = limit
      @scope = scope
      @vector_store = vector_store
    end

    def call
      validate!

      vector = chunk_vector

      unless valid_embedding?(vector)
        raise InvalidChunkError,
              "chunk deve ter um vetor válido armazenado no Qdrant"
      end

      duplicates = find_duplicates(vector)

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

    attr_reader :chunk, :minimum_similarity, :limit, :scope, :vector_store

    def validate!
      return if chunk.is_a?(DocumentChunk) && chunk.persisted?

      raise InvalidChunkError,
            "chunk deve ser um DocumentChunk persistido"
    end

    def valid_embedding?(embedding)
      embedding.is_a?(Array) &&
        embedding.any? &&
        embedding.all? { |value| value.is_a?(Numeric) }
    end

    # Chunks recém-criados já têm o vetor em memória (Documents::CreateChunkService
    # atribui chunk.embedding); chunks apenas carregados do banco (ex.:
    # DocumentDeduplicationScanService) precisam buscar o vetor no Qdrant.
    def chunk_vector
      return chunk.embedding if valid_embedding?(chunk.embedding)

      point =
        vector_store.retrieve(
          collection: Ai::Configuration::QDRANT_DOCUMENT_CHUNKS_COLLECTION,
          ids: [ chunk.id ]
        ).first

      point&.vector
    end

    def find_duplicates(vector)
      candidate_ids = scope.where.not(id: chunk.id).pluck(:id)

      return [] if candidate_ids.empty?

      points =
        vector_store.search(
          collection: Ai::Configuration::QDRANT_DOCUMENT_CHUNKS_COLLECTION,
          vector: vector,
          limit: limit,
          ids: candidate_ids
        )

      chunks_by_id = DocumentChunk.where(id: points.map(&:id)).index_by(&:id)

      points.filter_map do |point|
        similarity = point.score.to_f.clamp(0.0, 1.0)

        next if similarity < minimum_similarity

        candidate_chunk = chunks_by_id[point.id]

        next unless candidate_chunk

        Candidate.new(chunk: candidate_chunk, similarity: similarity)
      end
    end
  end
end
