require "rails_helper"

RSpec.describe Documents::MetadataScopeBuilder do
  let(:account) { create(:account) }

  def build_document_with_chunk(ramo:, seguradora:, vigencia_ano:, position: 0)
    document = Document.create!(
      title: "Documento #{ramo}-#{seguradora}-#{vigencia_ano}-#{SecureRandom.hex(2)}",
      content: "Conteúdo qualquer.",
      status: "completed",
      account: account,
      ramo: ramo,
      seguradora: seguradora,
      vigencia_ano: vigencia_ano
    )

    document.document_chunks.create!(
      content: "Trecho do documento #{ramo}.",
      position: position,
      embedding: Array.new(1536, 0.01)
    )
  end

  it "filters chunks by ramo case-insensitively" do
    match = build_document_with_chunk(ramo: "Auto", seguradora: "Acme", vigencia_ano: 2030)
    build_document_with_chunk(ramo: "Vida", seguradora: "Acme", vigencia_ano: 2030)

    scope = Documents::MetadataScopeBuilder.call(
      scope: DocumentChunk.all,
      filters: Documents::MetadataFilters.empty.with(ramo: "auto")
    )

    expect(scope.pluck(:id)).to eq([ match.id ])
  end

  it "combines multiple filters as AND conditions" do
    match = build_document_with_chunk(ramo: "Auto", seguradora: "Acme", vigencia_ano: 2030)
    build_document_with_chunk(ramo: "Auto", seguradora: "Beta", vigencia_ano: 2030)

    scope = Documents::MetadataScopeBuilder.call(
      scope: DocumentChunk.all,
      filters: Documents::MetadataFilters.empty.with(ramo: "auto", seguradora: "acme")
    )

    expect(scope.pluck(:id)).to eq([ match.id ])
  end

  it "filters by vigencia_ano" do
    match = build_document_with_chunk(ramo: "Auto", seguradora: "Acme", vigencia_ano: 2030)
    build_document_with_chunk(ramo: "Auto", seguradora: "Acme", vigencia_ano: 2031)

    scope = Documents::MetadataScopeBuilder.call(
      scope: DocumentChunk.all,
      filters: Documents::MetadataFilters.empty.with(vigencia_ano: 2030)
    )

    expect(scope.pluck(:id)).to eq([ match.id ])
  end

  it "returns everything in scope when the filters are empty" do
    build_document_with_chunk(ramo: "Auto", seguradora: "Acme", vigencia_ano: 2030)
    build_document_with_chunk(ramo: "Vida", seguradora: "Beta", vigencia_ano: 2031)

    scope = Documents::MetadataScopeBuilder.call(scope: DocumentChunk.all, filters: Documents::MetadataFilters.empty)

    expect(scope.count).to eq(2)
  end

  it "raises for a scope that is not an ActiveRecord relation" do
    expect do
      Documents::MetadataScopeBuilder.call(scope: [], filters: Documents::MetadataFilters.empty)
    end.to raise_error(Documents::MetadataScopeBuilder::InvalidScopeError)
  end

  it "raises for filters that are not a Documents::MetadataFilters" do
    expect do
      Documents::MetadataScopeBuilder.call(scope: DocumentChunk.all, filters: { ramo: "auto" })
    end.to raise_error(Documents::MetadataScopeBuilder::InvalidFiltersError)
  end
end
