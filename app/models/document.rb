require "digest"

class Document < ApplicationRecord
  STATUSES = %w[
    pending
    queued
    processing
    completed
    failed
  ].freeze

  belongs_to :account

  has_many(
    :document_chunks,
    dependent: :destroy,
    inverse_of: :document
  )

  validates :title, presence: true
  validates :content, presence: true
  validates :status, inclusion: { in: STATUSES }

  validates :vigencia_ano,
            numericality: {
              only_integer: true,
              greater_than: 1900,
              less_than: 2200
            },
            allow_nil: true

  before_validation :set_default_status, on: :create
  before_validation :generate_content_hash

  scope :by_ramo, lambda { |value|
    where("LOWER(documents.ramo) = ?", value.to_s.downcase)
  }

  scope :by_seguradora, lambda { |value|
    where("LOWER(documents.seguradora) = ?", value.to_s.downcase)
  }

  scope :by_cliente, lambda { |value|
    where("LOWER(documents.cliente) = ?", value.to_s.downcase)
  }

  scope :by_tipo_documento, lambda { |value|
    where(
      "LOWER(documents.tipo_documento) = ?",
      value.to_s.downcase
    )
  }

  scope :by_vigencia_ano, lambda { |value|
    where(vigencia_ano: value)
  }

  # Aula 48: hash usado pra saber se o conteúdo mudou desde a última
  # ingestão completa (metadata["ingested_content_hash"]), permitindo
  # pular reprocessamento redundante.
  def already_ingested_and_unchanged?
    status == "completed" &&
      content_hash.present? &&
      content_hash == metadata.to_h["ingested_content_hash"]
  end

  private

  def set_default_status
    self.status = "pending" if status.blank?
  end

  def generate_content_hash
    return if content.blank?

    self.content_hash = Digest::SHA256.hexdigest(
      normalized_content_for_hash
    )
  end

  def normalized_content_for_hash
    content.to_s
      .unicode_normalize(:nfkc)
      .gsub(/\r\n?/, "\n")
      .gsub(/[[:space:]]+/, " ")
      .strip
  end
end
