require "rails_helper"

RSpec.describe Documents::RerankingService do
  def multi_query_double_class
    @multi_query_double_class ||= Struct.new(:chunk, :similarity, :position, :multi_query_score, keyword_init: true)
  end

  let(:document) { create(:document) }

  def build_chunk(content:, position:)
    document.document_chunks.create!(content: content, position: position, embedding: Array.new(1536, 0.01))
  end

  it "lets a strong lexical match outrank a slightly higher raw vector similarity" do
    on_topic = build_chunk(content: "O prazo de vigência da apólice é de doze meses.", position: 0)
    off_topic = build_chunk(content: "O sistema realiza a averbação após localizar o documento fiscal.", position: 1)

    results = Documents::RerankingService.call(
      question: "Qual o prazo de vigência da apólice de seguro?",
      search_results: [
        Documents::VectorSearchService::Result.new(chunk: on_topic, distance: 0.3, similarity: 0.50, position: 1),
        Documents::VectorSearchService::Result.new(chunk: off_topic, distance: 0.2, similarity: 0.55, position: 2)
      ]
    )

    expect(results.map(&:chunk)).to eq([ on_topic, off_topic ])
    expect(results.first.rerank_score).to be_within(0.0001).of((0.50 * 0.70) + (0.75 * 0.25) + (1.0 * 0.05))
  end

  it "prefers multi_query_score over hybrid_score, and hybrid_score over similarity" do
    chunk = build_chunk(content: "Conteúdo neutro sem relação com a pergunta.", position: 0)

    from_multi_query = Documents::RerankingService.call(
      question: "pergunta qualquer",
      search_results: [ multi_query_double_class.new(chunk: chunk, similarity: 0.10, position: 1, multi_query_score: 0.77) ]
    ).first

    expect(from_multi_query.vector_score).to be_within(0.0001).of(0.77)

    from_hybrid = Documents::RerankingService.call(
      question: "pergunta qualquer",
      search_results: [
        Documents::HybridSearchService::Result.new(
          chunk: chunk, distance: nil, similarity: 0.99, vector_position: 1, text_position: nil,
          text_score: 0.0, normalized_text_score: 0.0, hybrid_score: 0.42, position: 1
        )
      ]
    ).first

    expect(from_hybrid.vector_score).to be_within(0.0001).of(0.42)

    from_similarity = Documents::RerankingService.call(
      question: "pergunta qualquer",
      search_results: [
        Documents::VectorSearchService::Result.new(chunk: chunk, distance: 0.1, similarity: 0.33, position: 1)
      ]
    ).first

    expect(from_similarity.vector_score).to be_within(0.0001).of(0.33)
  end

  it "clamps relevance scores that fall outside the 0..1 range" do
    chunk = build_chunk(content: "Conteúdo neutro.", position: 0)

    above_one = Documents::RerankingService.call(
      question: "pergunta qualquer",
      search_results: [ multi_query_double_class.new(chunk: chunk, similarity: 0.0, position: 1, multi_query_score: 1.5) ]
    ).first
    expect(above_one.vector_score).to be_within(0.0001).of(1.0)

    below_zero = Documents::RerankingService.call(
      question: "pergunta qualquer",
      search_results: [
        Documents::VectorSearchService::Result.new(chunk: chunk, distance: 1.0, similarity: -1.0, position: 1)
      ]
    ).first
    expect(below_zero.vector_score).to be_within(0.0001).of(0.0)
  end

  it "makes position_score the inverse of the original retrieval position" do
    first = build_chunk(content: "Conteúdo A.", position: 0)
    fourth = build_chunk(content: "Conteúdo B.", position: 1)

    results = Documents::RerankingService.call(
      question: "pergunta qualquer",
      search_results: [
        Documents::VectorSearchService::Result.new(chunk: first, distance: 0.1, similarity: 0.5, position: 1),
        Documents::VectorSearchService::Result.new(chunk: fourth, distance: 0.1, similarity: 0.5, position: 4)
      ]
    )

    by_chunk = results.index_by(&:chunk)
    expect(by_chunk[first].position_score).to be_within(0.0001).of(1.0)
    expect(by_chunk[fourth].position_score).to be_within(0.0001).of(0.25)
  end

  it "ignores stop words and short terms when matching question and chunk vocabulary" do
    chunk = build_chunk(content: "Sim, é a apólice correta.", position: 0)

    result = Documents::RerankingService.call(
      question: "É a apólice?",
      search_results: [
        Documents::VectorSearchService::Result.new(chunk: chunk, distance: 0.1, similarity: 0.5, position: 1)
      ]
    ).first

    expect(result.matched_terms).to eq([ "apolice" ])
    expect(result.lexical_score).to be_within(0.0001).of(1.0)
  end

  it "raises for a blank question" do
    chunk = build_chunk(content: "Conteúdo qualquer.", position: 0)

    expect do
      Documents::RerankingService.call(
        question: "   ",
        search_results: [
          Documents::VectorSearchService::Result.new(chunk: chunk, distance: 0.1, similarity: 0.5, position: 1)
        ]
      )
    end.to raise_error(Documents::RerankingService::InvalidQuestionError)
  end

  it "raises for malformed search results" do
    expect do
      Documents::RerankingService.call(
        question: "pergunta qualquer",
        search_results: [ { chunk: nil } ]
      )
    end.to raise_error(Documents::RerankingService::InvalidSearchResultsError)
  end

  it "raises for a non-positive limit" do
    chunk = build_chunk(content: "Conteúdo qualquer.", position: 0)

    expect do
      Documents::RerankingService.call(
        question: "pergunta qualquer",
        search_results: [
          Documents::VectorSearchService::Result.new(chunk: chunk, distance: 0.1, similarity: 0.5, position: 1)
        ],
        limit: 0
      )
    end.to raise_error(Documents::RerankingService::InvalidLimitError)
  end

  it "truncates to the limit and reassigns sequential positions while keeping the original position" do
    chunks = Array.new(3) { |index| build_chunk(content: "Conteúdo #{index}.", position: index) }

    search_results = chunks.each_with_index.map do |chunk, index|
      Documents::VectorSearchService::Result.new(
        chunk: chunk, distance: 0.1, similarity: 1.0 - (index * 0.1), position: index + 1
      )
    end

    results = Documents::RerankingService.call(
      question: "pergunta qualquer",
      search_results: search_results,
      limit: 2
    )

    expect(results.size).to eq(2)
    expect(results.map(&:position)).to eq([ 1, 2 ])
    expect(results.map(&:original_position)).to eq([ 1, 2 ])
  end
end
