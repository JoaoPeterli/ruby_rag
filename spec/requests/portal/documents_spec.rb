require "rails_helper"

RSpec.describe "Portal::Documents", type: :request do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account: account, password: "senha1234") }
  let!(:other_account_document) { create(:document, account: create(:account)) }

  def with_upload_enabled
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("DOCUMENT_UPLOAD_ENABLED", "false").and_return("true")

    yield
  end

  def uploaded_pdf(filename: "apolice.pdf")
    Rack::Test::UploadedFile.new(StringIO.new("conteúdo qualquer"), "application/pdf", original_filename: filename)
  end

  it "requires login" do
    get portal_documents_path

    expect(response).to redirect_to(new_portal_session_path)
  end

  it "lists only the current account's documents" do
    document = create(:document, account: account)
    sign_in_as_user(user)

    get portal_documents_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include(document.title)
    expect(response.body).not_to include(other_account_document.title)
  end

  it "shows a document scoped to the current account" do
    document = create(:document, account: account)
    sign_in_as_user(user)

    get portal_document_path(document)

    expect(response).to have_http_status(:success)
  end

  it "404s for a document belonging to another account" do
    sign_in_as_user(user)

    get portal_document_path(other_account_document)

    expect(response).to have_http_status(:not_found)
  end

  describe "when uploads are disabled" do
    it "redirects away from new and create" do
      sign_in_as_user(user)

      get new_portal_document_path
      expect(response).to redirect_to(portal_documents_path)

      post portal_documents_path, params: { document: { title: "Apólice", source_file: uploaded_pdf } }
      expect(response).to redirect_to(portal_documents_path)
    end
  end

  describe "when uploads are enabled" do
    it "renders the new form" do
      sign_in_as_user(user)

      with_upload_enabled { get new_portal_document_path }

      expect(response).to have_http_status(:success)
    end

    it "creates the document, enqueues OCR, and redirects with a notice" do
      sign_in_as_user(user)
      fake_job = Struct.new(:job_id).new(SecureRandom.uuid)
      allow(Documents::OcrExtractionJob).to receive(:perform_later).and_return(fake_job)

      with_upload_enabled do
        post portal_documents_path, params: { document: { title: "Apólice 123", source_file: uploaded_pdf } }
      end

      expect(response).to redirect_to(portal_documents_path)
      document = account.documents.order(:created_at).last
      expect(document.title).to eq("Apólice 123")
      expect(document.status).to eq("uploaded")
    end

    it "re-renders the form with an error when the file is missing" do
      sign_in_as_user(user)

      with_upload_enabled do
        post portal_documents_path, params: { document: { title: "Apólice 123" } }
      end

      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.documents.where(title: "Apólice 123")).to be_empty
    end
  end
end
