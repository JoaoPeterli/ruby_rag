require "rails_helper"

RSpec.describe "Admin::Queries", type: :request do
  let!(:operator) { create(:account, operator: true) }

  before { sign_in_as(operator) }

  it "redirects to login when there is no session" do
    delete admin_session_path

    get admin_queries_path

    expect(response).to redirect_to(new_admin_session_path)
  end

  it "lists queries" do
    RagQuery.create!(question: "Qual o prazo?", status: "completed", account: operator)

    get admin_queries_path

    expect(response).to have_http_status(:success)
    assert_select "td", text: "Qual o prazo?"
  end

  it "shows a query with its answer and retrieval results" do
    query = RagQuery.create!(question: "Qual o prazo?", status: "completed", account: operator)
    RagAnswer.create!(rag_query: query, answer: "30 dias.", model: "fake-model")

    get admin_query_path(query)

    expect(response).to have_http_status(:success)
    assert_select "p", text: /30 dias/
  end
end
