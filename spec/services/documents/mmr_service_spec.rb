require "rails_helper"

RSpec.describe Documents::MmrService do
  let(:document) { create(:document) }

  def build_chunk(position:, embedding:)
    document.document_chunks.create!(content: "Conteúdo #{position}.", position: position, embedding: embedding)
  end

  def unit_vector(index)
    vector = Array.new(1536, 0.0)
    vector[index] = 1.0
    vector
  end

  def reranked_result(chunk:, rerank_score:, position: 1)
    Documents::RerankingService::Result.new(
      chunk: chunk, distance: nil, similarity: rerank_score, position: position, original_position: position,
      vector_position: position, text_position: nil, text_score: 0.0, normalized_text_score: 0.0, hybrid_score: 0.0,
      multi_query_score: nil, matched_queries: [], query_match_count: 0, best_query_position: nil,
      vector_score: rerank_score, lexical_score: 0.0, position_score: 1.0, rerank_score: rerank_score,
      matched_terms: []
    )
  end

  it "prefers diversity over raw relevance once a similar result has already been selected" do
    chunk_a = build_chunk(position: 0, embedding: unit_vector(0))
    chunk_b = build_chunk(position: 1, embedding: unit_vector(0)) # embedding idêntico ao de A
    chunk_c = build_chunk(position: 2, embedding: unit_vector(1)) # ortogonal a A e B

    results = Documents::MmrService.call(
      results: [
        reranked_result(chunk: chunk_a, rerank_score: 0.90),
        reranked_result(chunk: chunk_b, rerank_score: 0.85),
        reranked_result(chunk: chunk_c, rerank_score: 0.60)
      ],
      limit: 2
    )

    # B tem relevância maior que C, mas é quase idêntico a A (já selecionado);
    # o MMR deve preferir a diversidade de C sobre a relevância bruta de B.
    expect(results.map(&:chunk)).to eq([ chunk_a, chunk_c ])
    expect(results.map(&:position)).to eq([ 1, 2 ])
  end

  it "gives the first pick zero redundancy and mmr_score equal to lambda times relevance" do
    chunk_a = build_chunk(position: 0, embedding: unit_vector(0))
    chunk_b = build_chunk(position: 1, embedding: unit_vector(1))

    results = Documents::MmrService.call(
      results: [
        reranked_result(chunk: chunk_a, rerank_score: 0.80),
        reranked_result(chunk: chunk_b, rerank_score: 0.20)
      ],
      limit: 1,
      lambda_value: 0.7
    )

    expect(results.first.redundancy_score).to be_within(0.0001).of(0.0)
    expect(results.first.mmr_score).to be_within(0.0001).of(0.7 * 0.80)
  end

  it "raises MissingEmbeddingError when a candidate chunk has no embedding" do
    chunk = document.document_chunks.create!(content: "Sem embedding.", position: 0)

    expect do
      Documents::MmrService.call(results: [ reranked_result(chunk: chunk, rerank_score: 0.5) ])
    end.to raise_error(Documents::MmrService::MissingEmbeddingError)
  end

  it "raises for malformed results" do
    expect do
      Documents::MmrService.call(results: [ { chunk: nil } ])
    end.to raise_error(Documents::MmrService::InvalidResultsError)
  end

  it "raises for a non-positive limit" do
    chunk = build_chunk(position: 0, embedding: unit_vector(0))

    expect do
      Documents::MmrService.call(results: [ reranked_result(chunk: chunk, rerank_score: 0.5) ], limit: 0)
    end.to raise_error(Documents::MmrService::InvalidLimitError)
  end

  it "raises for a lambda_value outside 0..1" do
    chunk = build_chunk(position: 0, embedding: unit_vector(0))

    expect do
      Documents::MmrService.call(
        results: [ reranked_result(chunk: chunk, rerank_score: 0.5) ],
        lambda_value: 1.5
      )
    end.to raise_error(Documents::MmrService::InvalidLambdaError)
  end
end
