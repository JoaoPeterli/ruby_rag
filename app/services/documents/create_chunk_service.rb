module Documents
  class CreateChunkService
    class Error < StandardError; end

    def self.call(document:, content:, position:, metadata: {})
      new(
        document: document,
        content: content,
        position: position,
        metadata: metadata
      ).call
    end

    def initialize(document:, content:, position:, metadata:)
      @document = document
      @content = content.to_s.strip
      @position = position
      @metadata = metadata
    end

    def call
      validate!

      embedding = Ai::EmbeddingService.call(texts: [@content]).first

      @document.document_chunks.create!(
        content: @content,
        position: @position,
        metadata: @metadata,
        embedding: embedding
      )
    rescue ActiveRecord::RecordInvalid => error
      raise Error, error.record.errors.full_messages.to_sentence
    end

    private

    def validate!
      raise Error, "Documento inválido" unless @document.persisted?
      raise Error, "O conteúdo está vazio" if @content.blank?
      raise Error, "A posição é obrigatória" if @position.nil?
    end
  end
end
