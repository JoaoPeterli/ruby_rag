require "rails_helper"

# Suíte de sanidade fim-a-fim: sobe o stack de middleware/routing de
# verdade e percorre uma jornada completa (não lógica isolada). Existe
# porque os últimos bugs reais encontrados neste projeto
# (Ai::Configuration::EMBEDDING_BATCH_SIZE inexistente, documentos presos
# em "processing", resources omitindo :new/:edit por causa de api_only)
# eram todos erros de wiring/config — nenhum teste unitário de lógica de
# negócio conseguiria pegar esse tipo de coisa; só rodar as rotas de
# verdade pega.
RSpec.describe "Smoke", type: :request do
  it "health check responds" do
    get "/up"

    expect(response).to have_http_status(:success)
  end

  it "full admin journey: login, every screen, logout" do
    operator = create(:account, operator: true)
    document = create(:document, title: "Manual", content: "Conteúdo.", account: operator, status: "completed")
    document.document_chunks.create!(content: "Trecho.", position: 0)
    RagQuery.create!(question: "Qual o prazo?", status: "completed", account: operator)
    RagEvalRun.create!(cases_count: 0, started_at: Time.current, finished_at: Time.current)

    get admin_dashboard_path
    expect(response).to redirect_to(new_admin_session_path)

    post admin_session_path, params: { api_key: operator.api_key }
    expect(response).to redirect_to(admin_dashboard_path)
    follow_redirect!
    expect(response).to have_http_status(:success)

    get root_path
    expect(response).to have_http_status(:success)

    get admin_documents_path
    expect(response).to have_http_status(:success)

    get admin_document_path(document)
    expect(response).to have_http_status(:success)

    get admin_queries_path
    expect(response).to have_http_status(:success)

    get admin_query_path(RagQuery.first)
    expect(response).to have_http_status(:success)

    get admin_evaluations_path
    expect(response).to have_http_status(:success)

    get admin_evaluation_path(RagEvalRun.first)
    expect(response).to have_http_status(:success)

    get admin_failures_path
    expect(response).to have_http_status(:success)

    get admin_accounts_path
    expect(response).to have_http_status(:success)

    get admin_account_path(operator)
    expect(response).to have_http_status(:success)

    get admin_audit_logs_path
    expect(response).to have_http_status(:success)

    delete admin_session_path
    expect(response).to redirect_to(new_admin_session_path)

    get admin_dashboard_path
    expect(response).to redirect_to(new_admin_session_path)
  end

  it "full API journey: ask a question through the real controller and get a grounded answer" do
    account = create(:account)
    document = create(:document, title: "Manual", content: "O prazo de averbação é de 5 dias.", account: account, status: "completed")
    embedding = Array.new(1536, 0.0).tap { |vector| vector[0] = 1.0 }

    document.document_chunks.create!(content: "O prazo de averbação é de 5 dias úteis.", position: 0)

    Ai::VectorStoreService.default.upsert(
      collection: Ai::Configuration::QDRANT_DOCUMENT_CHUNKS_COLLECTION,
      id: document.document_chunks.first.id,
      vector: embedding,
      payload: { document_id: document.id, account_id: account.id, position: 0 }
    )

    allow(Ai::EmbeddingService).to receive(:call) do |texts:, **_kwargs|
      Array.new(texts.size) { embedding }
    end
    allow(Ai::ChatCompletionService).to receive(:call).and_return(
      Ai::ChatCompletionService::Result.new(
        content: "O prazo é de 5 dias úteis [FONTE 1].",
        model: "fake-model",
        finish_reason: "stop",
        usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
        prompt_tokens: 10,
        completion_tokens: 5,
        total_tokens: 15,
        duration_ms: 1.0
      )
    )

    post(
      api_v1_questions_path,
      params: { question: "Qual o prazo de averbação?" }.to_json,
      headers: { "Authorization" => "Bearer #{account.api_key}", "Content-Type" => "application/json" }
    )

    expect(response).to have_http_status(:success)
    body = JSON.parse(response.body)
    expect(body["answer"]).to match(/5 dias/)
  end
end
