require "rails_helper"

RSpec.describe Documents::ContextCompression::SimilarityStrategy do
  let(:document) { create(:document) }

  def build_chunk(embedding:, position:)
    document.document_chunks.create!(
      content: "Conteúdo #{position}",
      position: position,
      embedding: embedding
    )
  end

  it "keeps only chunks at or above minimum_similarity, ordered by document/position" do
    query_embedding = Array.new(1536, 1.0)

    close = build_chunk(embedding: Array.new(1536, 1.0), position: 1)
    far = build_chunk(embedding: Array.new(1536, -1.0), position: 0)

    result = Documents::ContextCompression::SimilarityStrategy.call(
      question: "pergunta",
      chunks: [ far, close ],
      query_embedding: query_embedding,
      minimum_similarity: 0.5
    )

    expect(result.fetch(:chunks)).to eq([ close ])
    expect(result.fetch(:scores).fetch(close.id).fetch(:similarity)).to be_within(0.0001).of(1.0)
  end

  it "always keeps source chunks even when below minimum_similarity" do
    query_embedding = Array.new(1536, 1.0)

    source_chunk = build_chunk(embedding: Array.new(1536, -1.0), position: 0)

    result = Documents::ContextCompression::SimilarityStrategy.call(
      question: "pergunta",
      chunks: [ source_chunk ],
      query_embedding: query_embedding,
      source_chunk_ids: [ source_chunk.id ],
      minimum_similarity: 0.9
    )

    expect(result.fetch(:chunks)).to eq([ source_chunk ])
    expect(result.fetch(:scores).fetch(source_chunk.id).fetch(:source)).to be_truthy
  end

  it "keeps the single most similar chunk even if nothing meets the threshold and there are no source chunks" do
    query_embedding = Array.new(1536, 1.0)

    only_chunk = build_chunk(embedding: Array.new(1536, -1.0), position: 0)

    result = Documents::ContextCompression::SimilarityStrategy.call(
      question: "pergunta",
      chunks: [ only_chunk ],
      query_embedding: query_embedding,
      minimum_similarity: 0.9,
      preserve_source_chunks: false
    )

    expect(result.fetch(:chunks)).to eq([ only_chunk ])
  end

  it "respects max_chunks by keeping the most similar ones" do
    query_embedding = Array.new(1536, 1.0)

    best = build_chunk(embedding: Array.new(1536, 1.0), position: 0)
    middle_embedding = Array.new(768, 1.0) + Array.new(768, -1.0)
    middle = build_chunk(embedding: middle_embedding, position: 1)
    worst = build_chunk(embedding: Array.new(1536, -1.0), position: 2)

    result = Documents::ContextCompression::SimilarityStrategy.call(
      question: "pergunta",
      chunks: [ worst, middle, best ],
      query_embedding: query_embedding,
      minimum_similarity: -1.0,
      max_chunks: 2,
      preserve_source_chunks: false
    )

    expect(result.fetch(:chunks)).to eq([ best, middle ])
  end

  it "raises for a non-positive max_chunks" do
    chunk = build_chunk(embedding: Array.new(1536, 1.0), position: 0)

    expect do
      Documents::ContextCompression::SimilarityStrategy.call(
        question: "pergunta",
        chunks: [ chunk ],
        query_embedding: Array.new(1536, 1.0),
        max_chunks: 0
      )
    end.to raise_error(Documents::ContextCompression::SimilarityStrategy::InvalidMaxChunksError)
  end

  it "raises for a minimum_similarity outside -1..1" do
    chunk = build_chunk(embedding: Array.new(1536, 1.0), position: 0)

    expect do
      Documents::ContextCompression::SimilarityStrategy.call(
        question: "pergunta",
        chunks: [ chunk ],
        query_embedding: Array.new(1536, 1.0),
        minimum_similarity: 2.0
      )
    end.to raise_error(Documents::ContextCompression::SimilarityStrategy::InvalidMinimumSimilarityError)
  end

  it "raises for a blank question via the shared Strategy validation" do
    chunk = build_chunk(embedding: Array.new(1536, 1.0), position: 0)

    expect do
      Documents::ContextCompression::SimilarityStrategy.call(
        question: "   ",
        chunks: [ chunk ],
        query_embedding: Array.new(1536, 1.0)
      )
    end.to raise_error(Documents::ContextCompression::Strategy::InvalidQuestionError)
  end
end
