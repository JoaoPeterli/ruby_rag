require "rails_helper"

RSpec.describe Documents::Evaluation::MetricsCalculator do
  def build_source(chunk_id:, combined_score: nil, cross_encoder_score: nil, rerank_score: nil)
    Documents::QuestionAnsweringService::Source.new(
      chunk_id: chunk_id, document_id: 1, content: "trecho", position: 1, original_position: 1,
      vector_position: 1, text_position: nil, distance: nil, similarity: 0.5, text_score: 0.0,
      normalized_text_score: 0.0, hybrid_score: 0.5, multi_query_score: nil, matched_queries: [],
      query_match_count: 1, best_query_position: 1, rerank_score: rerank_score, lexical_score: 0.0,
      matched_terms: [], cross_encoder_score: cross_encoder_score, cross_encoder_reason: nil,
      combined_score: combined_score, mmr_score: nil, redundancy_score: nil,
      context_chunk_ids: [], cited: true
    )
  end

  def build_answer_result(sources: [], citation_coverage: 1.0, hallucination_check: nil, refused: false)
    Documents::QuestionAnsweringService::Result.new(
      question: "pergunta", effective_question: "pergunta", answer: "resposta", sources: sources,
      search_query: "pergunta", model: "fake-model", finish_reason: "stop", usage: {},
      prompt_tokens: 1, completion_tokens: 1, total_tokens: 2, citations: [],
      citation_coverage: citation_coverage, grounded: true, refused: refused,
      hallucination_check: hallucination_check, confidence_score: 0.9, confidence_level: "high",
      cache_hit: false, cache_similarity: nil, query_expansion_duration_ms: nil,
      retrieval_duration_ms: 1.0, duration_ms: 2.0, rag_query_id: nil, rag_answer_id: nil
    )
  end

  def build_eval_case(expected_chunk_ids: [], expected_answer: "resposta esperada")
    create(:rag_eval_case, expected_answer: expected_answer, expected_chunk_ids: expected_chunk_ids)
  end

  it "computes retrieval precision and recall against the expected chunk ids" do
    eval_case = build_eval_case(expected_chunk_ids: [ 1, 2, 3 ])
    answer_result = build_answer_result(sources: [ build_source(chunk_id: 1), build_source(chunk_id: 4) ])

    metrics = Documents::Evaluation::MetricsCalculator.call(eval_case: eval_case, answer_result: answer_result)

    expect(metrics.retrieval_precision).to be_within(0.0001).of(0.5)
    expect(metrics.retrieval_recall).to be_within(0.0001).of(1.0 / 3)
  end

  it "retrieval precision and recall are nil when the eval case has no expected chunks" do
    eval_case = build_eval_case(expected_chunk_ids: [])
    answer_result = build_answer_result(sources: [ build_source(chunk_id: 1) ])

    metrics = Documents::Evaluation::MetricsCalculator.call(eval_case: eval_case, answer_result: answer_result)

    expect(metrics.retrieval_precision).to be_nil
    expect(metrics.retrieval_recall).to be_nil
  end

  it "chunk_relevance averages the best available score per source" do
    eval_case = build_eval_case
    answer_result = build_answer_result(sources: [
      build_source(chunk_id: 1, combined_score: 0.8),
      build_source(chunk_id: 2, cross_encoder_score: 0.6),
      build_source(chunk_id: 3, rerank_score: 0.4)
    ])

    metrics = Documents::Evaluation::MetricsCalculator.call(eval_case: eval_case, answer_result: answer_result)

    expect(metrics.chunk_relevance).to be_within(0.0001).of((0.8 + 0.6 + 0.4) / 3.0)
  end

  it "answer_faithfulness is one minus the hallucination rate" do
    eval_case = build_eval_case
    hallucination_check = Struct.new(:hallucination_rate).new(0.25)
    answer_result = build_answer_result(
      sources: [ build_source(chunk_id: 1) ],
      hallucination_check: hallucination_check
    )

    metrics = Documents::Evaluation::MetricsCalculator.call(eval_case: eval_case, answer_result: answer_result)

    expect(metrics.answer_faithfulness).to be_within(0.0001).of(0.75)
  end

  it "answer_faithfulness is nil when there is no hallucination check" do
    eval_case = build_eval_case
    answer_result = build_answer_result(sources: [ build_source(chunk_id: 1) ], hallucination_check: nil)

    metrics = Documents::Evaluation::MetricsCalculator.call(eval_case: eval_case, answer_result: answer_result)

    expect(metrics.answer_faithfulness).to be_nil
  end

  it "no_evidence_correct is true when a case that expects an answer was not refused" do
    eval_case = build_eval_case(expected_answer: "resposta esperada")
    answer_result = build_answer_result(refused: false)

    metrics = Documents::Evaluation::MetricsCalculator.call(eval_case: eval_case, answer_result: answer_result)

    expect(metrics.no_evidence_correct).to be_truthy
  end

  it "no_evidence_correct is true when a case with no expected answer was refused" do
    eval_case = build_eval_case(expected_answer: nil)
    answer_result = build_answer_result(refused: true)

    metrics = Documents::Evaluation::MetricsCalculator.call(eval_case: eval_case, answer_result: answer_result)

    expect(metrics.no_evidence_correct).to be_truthy
  end

  it "no_evidence_correct is false when a case with no expected answer was answered anyway" do
    eval_case = build_eval_case(expected_answer: nil)
    answer_result = build_answer_result(refused: false)

    metrics = Documents::Evaluation::MetricsCalculator.call(eval_case: eval_case, answer_result: answer_result)

    expect(metrics.no_evidence_correct).to be_falsey
  end

  it "raises for a non RagEvalCase" do
    expect do
      Documents::Evaluation::MetricsCalculator.call(eval_case: nil, answer_result: build_answer_result)
    end.to raise_error(Documents::Evaluation::MetricsCalculator::InvalidEvalCaseError)
  end

  it "raises for an answer_result of the wrong type" do
    eval_case = build_eval_case

    expect do
      Documents::Evaluation::MetricsCalculator.call(eval_case: eval_case, answer_result: nil)
    end.to raise_error(Documents::Evaluation::MetricsCalculator::InvalidAnswerResultError)
  end
end
