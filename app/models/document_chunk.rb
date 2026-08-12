require "digest"

class DocumentChunk < ApplicationRecord
  belongs_to(
    :document,
    inverse_of: :document_chunks
  )

  belongs_to :account, optional: true

  # Não é mais uma coluna: o vetor mora no Qdrant. Quem faz busca vetorial
  # (Documents::VectorSearchService) preenche isso com o vetor retornado
  # pelo Qdrant, pra MmrService/ContextCompression::SimilarityStrategy
  # continuarem calculando cosseno em Ruby sobre chunks já recuperados.
  attr_accessor :embedding

  scope :ordered, -> { order(:position) }

  before_validation :generate_content_hash
  before_validation :inherit_account_from_document

  after_destroy :delete_from_vector_store


  validates :content, presence: true
  validates :position,
            presence: true,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0
            }

  validates :position,
            uniqueness: {
              scope: :document_id
            }


  validates(
    :content_hash,
    presence: true,
    uniqueness: {
      scope: :document_id,
      message: "já existe para este documento"
    }
  )



  private

  # Denormalizado a partir do documento pra buscas vetoriais/textuais
  # não precisarem de JOIN só pra filtrar por conta.
  def inherit_account_from_document
    self.account_id ||= document&.account_id
  end

  def generate_content_hash
    return if content.blank?

    self.content_hash = Digest::SHA256.hexdigest(
      normalized_content
    )
  end

  def normalized_content
    content.to_s
      .unicode_normalize(:nfkc)
      .gsub(/\r\n?/, "\n")
      .gsub(/[[:space:]]+/, " ")
      .strip
  end

  def delete_from_vector_store
    Ai::VectorStoreService.default.delete(
      collection: Ai::Configuration::QDRANT_DOCUMENT_CHUNKS_COLLECTION,
      ids: [ id ]
    )
  end
end
