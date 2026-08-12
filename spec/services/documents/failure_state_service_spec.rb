require "rails_helper"

RSpec.describe Documents::FailureStateService do
  it "marks the document as failed and records the error when the run matches" do
    document = create(:document, status: "processing", metadata: { "ingestion_run_id" => "run-123" })

    Documents::FailureStateService.call(
      document_id: document.id, run_id: "run-123", error: RuntimeError.new("falhou")
    )

    document.reload
    expect(document.status).to eq("failed")
    expect(document.metadata["ingestion_error_class"]).to eq("RuntimeError")
    expect(document.metadata["ingestion_error"]).to eq("falhou")
  end

  it "does nothing when the document no longer exists" do
    expect do
      Documents::FailureStateService.call(document_id: -1, run_id: "run-123", error: RuntimeError.new("falhou"))
    end.not_to raise_error
  end

  it "does nothing when the run_id no longer matches the document's current run" do
    document = create(:document, status: "processing", metadata: { "ingestion_run_id" => "run-current" })

    Documents::FailureStateService.call(
      document_id: document.id, run_id: "run-stale", error: RuntimeError.new("falhou")
    )

    document.reload
    expect(document.status).to eq("processing")
  end
end
