require "rails_helper"

RSpec.describe "Api::V1::Questions", type: :request do
  let!(:account) { create(:account) }

  def auth_headers
    { "Authorization" => "Bearer #{account.api_key}", "Content-Type" => "application/json" }
  end

  it "rejects a question that is too long" do
    post(
      api_v1_questions_path,
      params: { question: "a" * (Api::V1::QuestionsController::MAX_QUESTION_LENGTH + 1) }.to_json,
      headers: auth_headers
    )

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["error"]).to match(/longa demais/i)
  end

  it "rejects a conversation_history with more turns than allowed" do
    history = Array.new(Api::V1::QuestionsController::MAX_HISTORY_TURNS + 1) do |index|
      { role: "user", content: "mensagem #{index}" }
    end

    post(
      api_v1_questions_path,
      params: { question: "pergunta válida", conversation_history: history }.to_json,
      headers: auth_headers
    )

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["error"]).to match(/histórico/i)
  end

  it "rejects a conversation_history turn longer than allowed" do
    history = [
      { role: "user", content: "a" * (Api::V1::QuestionsController::MAX_HISTORY_TURN_LENGTH + 1) }
    ]

    post(
      api_v1_questions_path,
      params: { question: "pergunta válida", conversation_history: history }.to_json,
      headers: auth_headers
    )

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["error"]).to match(/histórico/i)
  end

  it "rejects an unauthenticated request" do
    post api_v1_questions_path, params: { question: "pergunta" }.to_json, headers: { "Content-Type" => "application/json" }

    expect(response).to have_http_status(:unauthorized)
  end
end
