require "rails_helper"

RSpec.describe Documents::DocumentDeduplicationScanService do
  def duplicates_result_class
    @duplicates_result_class ||= Struct.new(:duplicates, keyword_init: true)
  end

  it "returns only the scan results that found duplicates" do
    document = create(:document)
    chunk_a = document.document_chunks.create!(content: "Chunk A.", position: 0, embedding: Array.new(1536, 0.01))
    chunk_b = document.document_chunks.create!(content: "Chunk B.", position: 1, embedding: Array.new(1536, 0.02))

    result_class = duplicates_result_class
    fake_deduplication_service = Class.new do
      define_singleton_method(:call) do |chunk:, minimum_similarity:|
        if chunk == chunk_a
          result_class.new(duplicates: [ chunk_b ])
        else
          result_class.new(duplicates: [])
        end
      end
    end

    results = Documents::DocumentDeduplicationScanService.call(
      document: document,
      deduplication_service: fake_deduplication_service
    )

    expect(results.size).to eq(1)
    expect(results.first.duplicates).to eq([ chunk_b ])
  end

  it "raises for a document that isn't persisted" do
    expect do
      Documents::DocumentDeduplicationScanService.call(document: Document.new)
    end.to raise_error(Documents::DocumentDeduplicationScanService::InvalidDocumentError)
  end

  it "wraps a deduplication service failure as Error" do
    document = create(:document)
    document.document_chunks.create!(content: "Chunk A.", position: 0, embedding: Array.new(1536, 0.01))

    raising_service = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise Documents::SemanticDeduplicationService::Error, "falha ao comparar" }
    end

    expect do
      Documents::DocumentDeduplicationScanService.call(document: document, deduplication_service: raising_service)
    end.to raise_error(Documents::DocumentDeduplicationScanService::Error)
  end
end
