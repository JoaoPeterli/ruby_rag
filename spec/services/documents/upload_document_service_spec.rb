require "rails_helper"

RSpec.describe Documents::UploadDocumentService do
  let(:account) { create(:account) }
  let(:file) { fixture_file_upload_for("apolice.pdf", "application/pdf") }

  def fixture_file_upload_for(filename, content_type)
    Rack::Test::UploadedFile.new(
      StringIO.new("conteúdo qualquer"),
      content_type,
      original_filename: filename
    )
  end

  it "creates the document as uploaded, attaches the file, and enqueues OCR" do
    stub_ocr_job_enqueue do
      document = Documents::UploadDocumentService.call(account: account, title: "Apólice 123", file: file)

      expect(document).to be_persisted
      expect(document.status).to eq("uploaded")
      expect(document.account).to eq(account)
      expect(document.source_file).to be_attached
      expect(document.metadata["ocr_run_id"]).to be_present
      expect(document.metadata["active_job_id"]).to be_present
    end
  end

  it "passes through the business metadata fields" do
    stub_ocr_job_enqueue do
      document = Documents::UploadDocumentService.call(
        account: account,
        title: "Apólice 123",
        file: file,
        ramo: "auto",
        seguradora: "Seguradora X",
        cliente: "Cliente Y",
        tipo_documento: "apolice",
        vigencia_ano: 2026
      )

      expect(document).to have_attributes(
        ramo: "auto",
        seguradora: "Seguradora X",
        cliente: "Cliente Y",
        tipo_documento: "apolice",
        vigencia_ano: 2026
      )
    end
  end

  it "raises for an unpersisted account" do
    expect do
      Documents::UploadDocumentService.call(account: Account.new, title: "Apólice 123", file: file)
    end.to raise_error(Documents::UploadDocumentService::InvalidAccountError)
  end

  it "raises when the title is blank" do
    expect do
      Documents::UploadDocumentService.call(account: account, title: "  ", file: file)
    end.to raise_error(Documents::UploadDocumentService::InvalidTitleError)
  end

  it "raises when no file is given" do
    expect do
      Documents::UploadDocumentService.call(account: account, title: "Apólice 123", file: nil)
    end.to raise_error(Documents::UploadDocumentService::MissingFileError)
  end

  it "marks the document as failed when enqueuing raises unexpectedly" do
    allow(Documents::OcrExtractionJob).to receive(:perform_later).and_raise("job enqueue broke")

    expect do
      Documents::UploadDocumentService.call(account: account, title: "Apólice 123", file: file)
    end.to raise_error(Documents::UploadDocumentService::Error)

    document = account.documents.last
    expect(document.status).to eq("failed")
    expect(document.metadata["ocr_error_class"]).to eq("RuntimeError")
  end

  def stub_ocr_job_enqueue
    fake_job = Struct.new(:job_id).new(SecureRandom.uuid)
    allow(Documents::OcrExtractionJob).to receive(:perform_later).and_return(fake_job)

    yield
  end
end
