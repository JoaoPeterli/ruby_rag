require "rails_helper"

RSpec.describe "Admin::Documents", type: :request do
  let!(:operator) { create(:account, operator: true) }

  before { sign_in_as(operator) }

  it "redirects to login when there is no session" do
    delete admin_session_path

    get admin_documents_path

    expect(response).to redirect_to(new_admin_session_path)
  end

  it "lists documents and filters by status" do
    create(:document, title: "Completo", account: operator, status: "completed")
    create(:document, title: "Falhou", account: operator, status: "failed")

    get admin_documents_path(status: "failed")

    expect(response).to have_http_status(:success)
    assert_select "td", text: "Falhou"
    assert_select "td", { text: "Completo", count: 0 }
  end

  it "shows a document with its chunks" do
    document = create(:document, title: "Manual", account: operator, status: "completed")
    document.document_chunks.create!(content: "Trecho.", position: 0)

    get admin_document_path(document)

    expect(response).to have_http_status(:success)
    assert_select "td", text: /Trecho/
  end
end
