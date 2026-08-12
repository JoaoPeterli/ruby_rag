require "rails_helper"

RSpec.describe Documents::CrossEncoder::Service do
  let(:document) { create(:document) }

  def build_chunk(position:)
    document.document_chunks.create!(
      content: "Conteúdo #{position}.",
      position: position,
      embedding: Array.new(1536, 0.01)
    )
  end

  def build_result(chunk, similarity:)
    Documents::VectorSearchService::Result.new(chunk: chunk, distance: 0.1, similarity: similarity, position: 1)
  end

  def build_strategy(evaluations_by_chunk_id:, model: "fake-model")
    Class.new do
      define_singleton_method(:call) do |question:, results:, **_opts|
        evaluations = results.map do |result|
          Documents::CrossEncoder::LlmBatchStrategy::Evaluation.new(
            chunk_id: result.chunk.id,
            score: evaluations_by_chunk_id.fetch(result.chunk.id),
            reason: "motivo"
          )
        end

        { evaluations: evaluations, model: model }
      end
    end
  end

  it "combines cross-encoder score and normalized retrieval score, filters and sorts" do
    chunk_a = build_chunk(position: 0)
    chunk_b = build_chunk(position: 1)
    chunk_c = build_chunk(position: 2)

    strategy = build_strategy(evaluations_by_chunk_id: {
      chunk_a.id => 0.9, chunk_b.id => 0.5, chunk_c.id => 0.1
    })

    result = Documents::CrossEncoder::Service.call(
      question: "pergunta",
      results: [
        build_result(chunk_a, similarity: 0.9),
        build_result(chunk_b, similarity: 0.6),
        build_result(chunk_c, similarity: 0.3)
      ],
      strategy: strategy
    )

    expect(result.results.map(&:chunk)).to eq([ chunk_a, chunk_b ])
    expect(result.original_count).to eq(3)
    expect(result.evaluated_count).to eq(3)
    expect(result.reranked_count).to eq(2)
    expect(result.average_score).to be_within(0.0001).of(0.5)
    expect(result.model).to eq("fake-model")
    expect(result.results.first.combined_score).to be_within(0.0001).of((0.9 * 0.75) + (1.0 * 0.25))
  end

  it "falls back to every candidate when none clears the minimum score" do
    chunk_a = build_chunk(position: 0)
    chunk_b = build_chunk(position: 1)

    strategy = build_strategy(evaluations_by_chunk_id: { chunk_a.id => 0.1, chunk_b.id => 0.05 })

    result = Documents::CrossEncoder::Service.call(
      question: "pergunta",
      results: [ build_result(chunk_a, similarity: 0.9), build_result(chunk_b, similarity: 0.1) ],
      strategy: strategy
    )

    expect(result.results.size).to eq(2)
  end

  it "raises for results that do not look like search results" do
    expect do
      Documents::CrossEncoder::Service.call(question: "pergunta", results: [ "not-a-result" ])
    end.to raise_error(Documents::CrossEncoder::Service::InvalidResultsError)
  end

  it "raises for a non-positive candidate_limit or rerank_limit" do
    chunk = build_chunk(position: 0)

    expect do
      Documents::CrossEncoder::Service.call(
        question: "pergunta",
        results: [ build_result(chunk, similarity: 0.5) ],
        candidate_limit: 0
      )
    end.to raise_error(Documents::CrossEncoder::Service::InvalidConfigurationError)
  end

  it "raises for a minimum_score outside 0..1" do
    chunk = build_chunk(position: 0)

    expect do
      Documents::CrossEncoder::Service.call(
        question: "pergunta",
        results: [ build_result(chunk, similarity: 0.5) ],
        minimum_score: 1.5
      )
    end.to raise_error(Documents::CrossEncoder::Service::InvalidConfigurationError)
  end

  it "raises when both weights are zero" do
    chunk = build_chunk(position: 0)

    expect do
      Documents::CrossEncoder::Service.call(
        question: "pergunta",
        results: [ build_result(chunk, similarity: 0.5) ],
        cross_encoder_weight: 0,
        retrieval_weight: 0
      )
    end.to raise_error(Documents::CrossEncoder::Service::InvalidConfigurationError)
  end

  it "wraps a strategy error as RerankError" do
    chunk = build_chunk(position: 0)

    raising_strategy = Class.new do
      define_singleton_method(:call) { |**_opts| raise Documents::CrossEncoder::Strategy::Error, "falhou" }
    end

    expect do
      Documents::CrossEncoder::Service.call(
        question: "pergunta",
        results: [ build_result(chunk, similarity: 0.5) ],
        strategy: raising_strategy
      )
    end.to raise_error(Documents::CrossEncoder::Service::RerankError)
  end

  it "wraps a malformed strategy result as RerankError" do
    chunk = build_chunk(position: 0)

    broken_strategy = Class.new do
      define_singleton_method(:call) { |**_opts| {} }
    end

    expect do
      Documents::CrossEncoder::Service.call(
        question: "pergunta",
        results: [ build_result(chunk, similarity: 0.5) ],
        strategy: broken_strategy
      )
    end.to raise_error(Documents::CrossEncoder::Service::RerankError)
  end
end
