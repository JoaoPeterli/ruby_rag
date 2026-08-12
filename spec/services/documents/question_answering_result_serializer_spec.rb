require "rails_helper"

RSpec.describe Documents::QuestionAnsweringResultSerializer do
  def citation_double_class
    @citation_double_class ||= Struct.new(:source_number, :chunk_id, :document_id, :position, keyword_init: true)
  end

  def build_source(content: "Conteúdo curto.")
    Documents::QuestionAnsweringService::Source.new(
      chunk_id: 1, document_id: 2, content: content, position: 1, original_position: 1,
      vector_position: 1, text_position: nil, distance: 0.1, similarity: 0.9, text_score: 0.0,
      normalized_text_score: 0.0, hybrid_score: 0.9, multi_query_score: nil, matched_queries: [],
      query_match_count: 1, best_query_position: 1, rerank_score: 0.9, lexical_score: 0.5,
      matched_terms: [ "apolice" ], cross_encoder_score: nil, cross_encoder_reason: nil,
      combined_score: nil, mmr_score: 0.9, redundancy_score: 0.0, context_chunk_ids: [ 1 ], cited: true
    )
  end

  def build_result(sources: [ build_source ], citations: [ citation_double_class.new(source_number: 1, chunk_id: 1, document_id: 2, position: 1) ])
    Documents::QuestionAnsweringService::Result.new(
      question: "Qual o prazo?", effective_question: "Qual o prazo da apólice?",
      answer: "O prazo é de doze meses [FONTE 1].", sources: sources, search_query: "prazo apólice",
      model: "fake-model", finish_reason: "stop", usage: { total_tokens: 20 }, prompt_tokens: 15,
      completion_tokens: 5, total_tokens: 20, citations: citations, citation_coverage: 1.0,
      grounded: true, refused: false, hallucination_check: nil, confidence_score: 0.9,
      confidence_level: "high", cache_hit: false, cache_similarity: nil,
      query_expansion_duration_ms: 2.0, retrieval_duration_ms: 10.0, duration_ms: 50.0,
      rag_query_id: 7, rag_answer_id: 9
    )
  end

  it "flattens the result, sources and citations into a plain hash" do
    serialized = Documents::QuestionAnsweringResultSerializer.call(result: build_result)

    expect(serialized[:answer]).to eq("O prazo é de doze meses [FONTE 1].")
    expect(serialized[:grounded]).to eq(true)
    expect(serialized[:rag_answer_id]).to eq(9)

    source = serialized[:sources].first
    expect(source[:chunk_id]).to eq(1)
    expect(source[:cited]).to eq(true)
    expect(source[:hybrid_score]).to eq(0.9)

    citation = serialized[:citations].first
    expect(citation[:source_number]).to eq(1)
    expect(citation[:document_id]).to eq(2)
  end

  it "truncates source content longer than 280 characters" do
    long_content = "a" * 400
    serialized = Documents::QuestionAnsweringResultSerializer.call(
      result: build_result(sources: [ build_source(content: long_content) ])
    )

    expect(serialized[:sources].first[:content].length).to eq(280)
  end

  it "handles a result with no sources or citations" do
    serialized = Documents::QuestionAnsweringResultSerializer.call(
      result: build_result(sources: [], citations: [])
    )

    expect(serialized[:sources]).to be_empty
    expect(serialized[:citations]).to be_empty
  end
end
