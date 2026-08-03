# frozen_string_literal: true

module Documents
  MetadataFilters = Data.define(
    :ramo,
    :seguradora,
    :cliente,
    :tipo_documento,
    :vigencia_ano,
    :metadata
  ) do
    def self.empty
      new(
        ramo: nil,
        seguradora: nil,
        cliente: nil,
        tipo_documento: nil,
        vigencia_ano: nil,
        metadata: {}
      )
    end

    def empty?
      ramo.blank? &&
        seguradora.blank? &&
        cliente.blank? &&
        tipo_documento.blank? &&
        vigencia_ano.blank? &&
        metadata.blank?
    end

    def to_h
      {
        ramo: ramo,
        seguradora: seguradora,
        cliente: cliente,
        tipo_documento: tipo_documento,
        vigencia_ano: vigencia_ano,
        metadata: metadata
      }.compact_blank
    end
  end
end
