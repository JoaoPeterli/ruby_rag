require "test_helper"

class Documents::RagPersistenceServiceTest < ActiveSupport::TestCase
  def build_qa_result(**overrides)
    Documents::QuestionAnsweringService::Result.new(
      **{
        question: "Pergunta de teste",
        effective_question: "Pergunta de teste",
        answer: "Resposta de teste",
        sources: [],
        search_query: "Pergunta de teste",
        model: "fake-model",
        finish_reason: "stop",
        usage: {},
        prompt_tokens: 10,
        completion_tokens: 5,
        total_tokens: 15,
        citations: [],
        citation_coverage: 1.0,
        grounded: true,
        refused: false,
        hallucination_check: nil,
        confidence_score: 0.9,
        confidence_level: "high",
        cache_hit: false,
        cache_similarity: nil,
        query_expansion_duration_ms: nil,
        retrieval_duration_ms: 10.0,
        duration_ms: 20.0,
        rag_query_id: nil,
        rag_answer_id: nil
      }.merge(overrides)
    )
  end

  test "persists the rag_query scoped to the given account" do
    account = Account.create!(name: "Conta de Persistencia")

    rag_query = Documents::RagPersistenceService.call(
      qa_result: build_qa_result,
      account_id: account.id
    )

    assert_equal account.id, rag_query.account_id
    assert_equal "Resposta de teste", rag_query.rag_answer.answer
  end

  test "persists with a nil account_id when none is given" do
    rag_query = Documents::RagPersistenceService.call(qa_result: build_qa_result)

    assert_nil rag_query.account_id
  end
end
