require "rails_helper"

RSpec.describe DocumentChunk do
  def build_chunk(document, **overrides)
    document.document_chunks.new({ content: "Trecho de teste.", position: 0 }.merge(overrides))
  end

  it "requires content and a non-negative integer position" do
    document = create(:document)

    chunk = build_chunk(document, content: nil, position: nil)
    expect(chunk).not_to be_valid
    expect(chunk.errors.attribute_names).to include(:content, :position)

    negative = build_chunk(document, position: -1)
    expect(negative).not_to be_valid
    expect(negative.errors.attribute_names).to include(:position)
  end

  it "requires position to be unique within the same document" do
    document = create(:document)
    build_chunk(document, position: 0).save!

    duplicate = build_chunk(document, content: "Outro trecho.", position: 0)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors.attribute_names).to include(:position)
  end

  it "allows the same position across different documents" do
    first_document = create(:document)
    second_document = create(:document)

    build_chunk(first_document, position: 0).save!
    other = build_chunk(second_document, position: 0)

    expect(other).to be_valid
  end

  it "generates a content_hash automatically" do
    chunk = build_chunk(create(:document))
    chunk.save!

    expect(chunk.content_hash).to be_present
  end

  it "rejects duplicate content within the same document" do
    document = create(:document)
    build_chunk(document, content: "Conteudo repetido", position: 0).save!

    duplicate = build_chunk(document, content: "Conteudo repetido", position: 1)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors.attribute_names).to include(:content_hash)
  end

  it "deletes the chunk's point from the vector store after destroy" do
    chunk = build_chunk(create(:document))
    chunk.save!

    Ai::VectorStoreService.default.upsert(
      collection: Ai::Configuration::QDRANT_DOCUMENT_CHUNKS_COLLECTION,
      id: chunk.id,
      vector: Array.new(1536, 0.0)
    )

    chunk.destroy!

    expect(
      Ai::VectorStoreService.default.retrieve(
        collection: Ai::Configuration::QDRANT_DOCUMENT_CHUNKS_COLLECTION,
        ids: [ chunk.id ]
      )
    ).to be_empty
  end

  it "orders chunks by position via the ordered scope" do
    document = create(:document)
    build_chunk(document, content: "Terceiro", position: 2).save!
    build_chunk(document, content: "Primeiro", position: 0).save!
    build_chunk(document, content: "Segundo", position: 1).save!

    expect(document.document_chunks.ordered.pluck(:position)).to eq([ 0, 1, 2 ])
  end
end
