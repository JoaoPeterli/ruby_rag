require "test_helper"

class Documents::RecordFeedbackServiceTest < ActiveSupport::TestCase
  def build_answer(account:)
    rag_query = RagQuery.create!(
      question: "Pergunta de teste",
      status: "completed",
      account: account
    )

    RagAnswer.create!(rag_query: rag_query, answer: "Resposta de teste")
  end

  test "records feedback for an answer belonging to the given account" do
    account = Account.create!(name: "Conta A")
    answer = build_answer(account: account)

    feedback = Documents::RecordFeedbackService.call(
      rag_answer_id: answer.id,
      rating: "positive",
      account_id: account.id
    )

    assert_equal "positive", feedback.rating
    assert_equal answer.id, feedback.rag_answer_id
  end

  test "raises AnswerNotFoundError when the answer belongs to a different account" do
    account_a = Account.create!(name: "Conta A")
    account_b = Account.create!(name: "Conta B")
    answer = build_answer(account: account_b)

    assert_raises(Documents::RecordFeedbackService::AnswerNotFoundError) do
      Documents::RecordFeedbackService.call(
        rag_answer_id: answer.id,
        rating: "positive",
        account_id: account_a.id
      )
    end
  end

  test "cross-account and truly nonexistent ids raise identically formatted errors, without extra detail that would leak existence" do
    account_a = Account.create!(name: "Conta A")
    account_b = Account.create!(name: "Conta B")
    answer = build_answer(account: account_b)
    nonexistent_id = answer.id + 999_999

    cross_account_error =
      assert_raises(Documents::RecordFeedbackService::AnswerNotFoundError) do
        Documents::RecordFeedbackService.call(
          rag_answer_id: answer.id,
          rating: "positive",
          account_id: account_a.id
        )
      end

    nonexistent_error =
      assert_raises(Documents::RecordFeedbackService::AnswerNotFoundError) do
        Documents::RecordFeedbackService.call(
          rag_answer_id: nonexistent_id,
          rating: "positive",
          account_id: account_a.id
        )
      end

    # As mensagens têm o mesmo template (só variam pelo id que o
    # próprio chamador já forneceu) — nenhuma delas expõe se o motivo
    # foi "não existe" ou "existe, mas é de outra conta".
    assert_equal "Nenhuma resposta encontrada com id #{answer.id}", cross_account_error.message
    assert_equal "Nenhuma resposta encontrada com id #{nonexistent_id}", nonexistent_error.message
  end

  test "allows access to answers with no account when account_id is nil" do
    answer = build_answer(account: nil)

    feedback = Documents::RecordFeedbackService.call(
      rag_answer_id: answer.id,
      rating: "negative",
      account_id: nil
    )

    assert_equal "negative", feedback.rating
  end

  test "raises InvalidRatingError for an unknown rating" do
    account = Account.create!(name: "Conta A")
    answer = build_answer(account: account)

    assert_raises(Documents::RecordFeedbackService::InvalidRatingError) do
      Documents::RecordFeedbackService.call(
        rag_answer_id: answer.id,
        rating: "neutral",
        account_id: account.id
      )
    end
  end
end
