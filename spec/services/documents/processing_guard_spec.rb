require "rails_helper"

RSpec.describe Documents::ProcessingGuard do
  def enqueued_document(run_id: "run-1", status: "queued")
    create(:document, status: status, metadata: { "ingestion_run_id" => run_id, "ingestion_attempts" => 0 })
  end

  it "registers a processing attempt for a queued document with a matching run_id" do
    document = enqueued_document(run_id: "run-1")

    result = Documents::ProcessingGuard.call(document: document, run_id: "run-1")

    expect(result.id).to eq(document.id)
    expect(result.status).to eq("processing")
    expect(result.metadata["ingestion_attempts"]).to eq(1)
    expect(result.metadata["processing_started_at"]).to be_present
  end

  it "increments ingestion_attempts on a second call with the same run_id" do
    document = enqueued_document(run_id: "run-1")

    Documents::ProcessingGuard.call(document: document, run_id: "run-1")
    result = Documents::ProcessingGuard.call(document: document, run_id: "run-1")

    expect(result.metadata["ingestion_attempts"]).to eq(2)
  end

  it "raises StaleRunError when the run_id does not match the document's current run" do
    document = enqueued_document(run_id: "run-1")

    expect do
      Documents::ProcessingGuard.call(document: document, run_id: "run-2")
    end.to raise_error(Documents::ProcessingGuard::StaleRunError)
  end

  it "raises StaleRunError for a blank run_id" do
    document = enqueued_document(run_id: "run-1")

    expect do
      Documents::ProcessingGuard.call(document: document, run_id: "  ")
    end.to raise_error(Documents::ProcessingGuard::StaleRunError)
  end

  it "raises InvalidStatusError when the document is not queued or processing" do
    document = enqueued_document(run_id: "run-1", status: "completed")

    expect do
      Documents::ProcessingGuard.call(document: document, run_id: "run-1")
    end.to raise_error(Documents::ProcessingGuard::InvalidStatusError)
  end

  it "raises InvalidDocumentError for a document that is not persisted" do
    document = build(:document, title: "Não salvo")

    expect do
      Documents::ProcessingGuard.call(document: document, run_id: "run-1")
    end.to raise_error(Documents::ProcessingGuard::InvalidDocumentError)
  end
end
