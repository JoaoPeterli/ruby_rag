require "rails_helper"

RSpec.describe Documents::RecordFeedbackService do
  def build_answer(account:)
    rag_query = RagQuery.create!(question: "Pergunta de teste", status: "completed", account: account)

    RagAnswer.create!(rag_query: rag_query, answer: "Resposta de teste")
  end

  it "records feedback for an answer belonging to the given account" do
    account = create(:account)
    answer = build_answer(account: account)

    feedback = Documents::RecordFeedbackService.call(
      rag_answer_id: answer.id,
      rating: "positive",
      account_id: account.id
    )

    expect(feedback.rating).to eq("positive")
    expect(feedback.rag_answer_id).to eq(answer.id)
  end

  it "raises AnswerNotFoundError when the answer belongs to a different account" do
    account_a = create(:account)
    account_b = create(:account)
    answer = build_answer(account: account_b)

    expect do
      Documents::RecordFeedbackService.call(
        rag_answer_id: answer.id,
        rating: "positive",
        account_id: account_a.id
      )
    end.to raise_error(Documents::RecordFeedbackService::AnswerNotFoundError)
  end

  it "raises identically formatted errors for cross-account and truly nonexistent ids, without extra detail that would leak existence" do
    account_a = create(:account)
    account_b = create(:account)
    answer = build_answer(account: account_b)
    nonexistent_id = answer.id + 999_999

    cross_account_error = nil
    begin
      Documents::RecordFeedbackService.call(rag_answer_id: answer.id, rating: "positive", account_id: account_a.id)
    rescue Documents::RecordFeedbackService::AnswerNotFoundError => e
      cross_account_error = e
    end

    nonexistent_error = nil
    begin
      Documents::RecordFeedbackService.call(rag_answer_id: nonexistent_id, rating: "positive", account_id: account_a.id)
    rescue Documents::RecordFeedbackService::AnswerNotFoundError => e
      nonexistent_error = e
    end

    # As mensagens têm o mesmo template (só variam pelo id que o
    # próprio chamador já forneceu) — nenhuma delas expõe se o motivo
    # foi "não existe" ou "existe, mas é de outra conta".
    expect(cross_account_error.message).to eq("Nenhuma resposta encontrada com id #{answer.id}")
    expect(nonexistent_error.message).to eq("Nenhuma resposta encontrada com id #{nonexistent_id}")
  end

  it "allows access to answers with no account when account_id is nil" do
    answer = build_answer(account: nil)

    feedback = Documents::RecordFeedbackService.call(
      rag_answer_id: answer.id,
      rating: "negative",
      account_id: nil
    )

    expect(feedback.rating).to eq("negative")
  end

  it "raises InvalidRatingError for an unknown rating" do
    account = create(:account)
    answer = build_answer(account: account)

    expect do
      Documents::RecordFeedbackService.call(
        rag_answer_id: answer.id,
        rating: "neutral",
        account_id: account.id
      )
    end.to raise_error(Documents::RecordFeedbackService::InvalidRatingError)
  end
end
