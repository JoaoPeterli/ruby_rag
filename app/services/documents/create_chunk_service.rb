module Documents
  class CreateChunkService
    class Error < StandardError; end

    def self.call(document:, content:, position:, metadata: {}, vector_store: Ai::VectorStoreService.default)
      new(
        document: document,
        content: content,
        position: position,
        metadata: metadata,
        vector_store: vector_store
      ).call
    end

    def initialize(document:, content:, position:, metadata:, vector_store: Ai::VectorStoreService.default)
      @document = document
      @content = content.to_s.strip
      @position = position
      @metadata = metadata
      @vector_store = vector_store
    end

    def call
      validate!

      embedding = Ai::EmbeddingService.call(texts: [@content]).first

      chunk = @document.document_chunks.create!(
        content: @content,
        position: @position,
        metadata: @metadata
      )

      upsert_vector(chunk, embedding)

      chunk.embedding = embedding
      chunk
    rescue ActiveRecord::RecordInvalid => error
      raise Error, error.record.errors.full_messages.to_sentence
    end

    private

    def upsert_vector(chunk, embedding)
      @vector_store.upsert(
        collection: Ai::Configuration::QDRANT_DOCUMENT_CHUNKS_COLLECTION,
        id: chunk.id,
        vector: embedding,
        payload: {
          document_id: chunk.document_id,
          account_id: chunk.account_id,
          position: chunk.position
        }
      )
    end

    def validate!
      raise Error, "Documento inválido" unless @document.persisted?
      raise Error, "O conteúdo está vazio" if @content.blank?
      raise Error, "A posição é obrigatória" if @position.nil?
    end
  end
end
