require "rails_helper"

RSpec.describe Documents::ParentDocumentRetrievalService do
  def source_result_double_class
    @source_result_double_class ||= Struct.new(:chunk, keyword_init: true)
  end

  def build_document_with_chunks(count:)
    document = create(:document, title: "Manual #{SecureRandom.hex(2)}")

    (0...count).map do |position|
      document.document_chunks.create!(content: "Trecho #{position}.", position: position, embedding: Array.new(1536, 0.01))
    end
  end

  it "expands a single hit into its surrounding window, ordered by position" do
    chunks = build_document_with_chunks(count: 10)
    source_chunk = chunks[5]

    result = Documents::ParentDocumentRetrievalService.call(
      results: [ source_result_double_class.new(chunk: source_chunk) ],
      window_size: 2
    )

    expect(result.chunks.map(&:id)).to eq(chunks[3..7].map(&:id))
    expect(result.groups.size).to eq(1)
    expect(result.groups.first.source_chunk_ids).to eq([ source_chunk.id ])
    expect(result.groups.first.minimum_position).to eq(3)
    expect(result.groups.first.maximum_position).to eq(7)
    expect(result.source_chunk_ids).to eq([ source_chunk.id ])
  end

  it "clamps the window's minimum position at zero instead of going negative" do
    chunks = build_document_with_chunks(count: 10)
    source_chunk = chunks[1]

    result = Documents::ParentDocumentRetrievalService.call(
      results: [ source_result_double_class.new(chunk: source_chunk) ],
      window_size: 5
    )

    expect(result.groups.first.minimum_position).to eq(0)
    expect(result.groups.first.maximum_position).to eq(6)
  end

  it "groups source chunks from different documents separately" do
    first_document_chunks = build_document_with_chunks(count: 3)
    second_document_chunks = build_document_with_chunks(count: 3)

    result = Documents::ParentDocumentRetrievalService.call(
      results: [
        source_result_double_class.new(chunk: first_document_chunks[0]),
        source_result_double_class.new(chunk: second_document_chunks[0])
      ],
      window_size: 1
    )

    expect(result.groups.size).to eq(2)
  end

  it "respects max_chunks, prioritizing the original source chunks first" do
    chunks = build_document_with_chunks(count: 10)
    source_chunk = chunks[5]

    result = Documents::ParentDocumentRetrievalService.call(
      results: [ source_result_double_class.new(chunk: source_chunk) ],
      window_size: 2,
      max_chunks: 2
    )

    expect(result.chunks.size).to eq(2)
    expect(result.chunks.map(&:id)).to include(source_chunk.id)
  end

  it "raises for malformed results" do
    expect do
      Documents::ParentDocumentRetrievalService.call(results: [ { chunk: nil } ])
    end.to raise_error(Documents::ParentDocumentRetrievalService::InvalidResultsError)
  end

  it "raises for a negative window_size" do
    chunk = build_document_with_chunks(count: 1).first

    expect do
      Documents::ParentDocumentRetrievalService.call(
        results: [ source_result_double_class.new(chunk: chunk) ],
        window_size: -1
      )
    end.to raise_error(Documents::ParentDocumentRetrievalService::InvalidWindowSizeError)
  end

  it "raises for a non-positive max_chunks" do
    chunk = build_document_with_chunks(count: 1).first

    expect do
      Documents::ParentDocumentRetrievalService.call(
        results: [ source_result_double_class.new(chunk: chunk) ],
        max_chunks: 0
      )
    end.to raise_error(Documents::ParentDocumentRetrievalService::InvalidMaxChunksError)
  end
end
