require "rails_helper"

RSpec.describe Documents::ReconcileStaleProcessingDocumentsService do
  let(:account) { create(:account) }

  def build_document(status:, processing_last_attempt_at: nil, processing_started_at: nil)
    metadata = {}
    metadata["processing_last_attempt_at"] = processing_last_attempt_at.iso8601 if processing_last_attempt_at
    metadata["processing_started_at"] = processing_started_at.iso8601 if processing_started_at

    create(:document, status: status, account: account, metadata: metadata)
  end

  it "moves a processing document with no recent attempt to failed" do
    document = build_document(status: "processing", processing_last_attempt_at: 1.hour.ago)

    reconciled = Documents::ReconcileStaleProcessingDocumentsService.call(stale_after: 30.minutes)

    expect(reconciled).to eq([ { document_id: document.id } ])

    document.reload
    expect(document.status).to eq("failed")
    expect(document.metadata["ingestion_error_class"]).to eq(
      "Documents::ReconcileStaleProcessingDocumentsService::StaleProcessingError"
    )
    expect(document.metadata["ingestion_error"]).to be_present
    expect(document.metadata["ingestion_failed_at"]).to be_present
  end

  it "leaves a recently-attempted processing document alone" do
    document = build_document(status: "processing", processing_last_attempt_at: 1.minute.ago)

    reconciled = Documents::ReconcileStaleProcessingDocumentsService.call(stale_after: 30.minutes)

    expect(reconciled).to be_empty

    document.reload
    expect(document.status).to eq("processing")
  end

  it "falls back to processing_started_at when there was no retry attempt yet" do
    document = build_document(status: "processing", processing_started_at: 1.hour.ago)

    reconciled = Documents::ReconcileStaleProcessingDocumentsService.call(stale_after: 30.minutes)

    expect(reconciled).to eq([ { document_id: document.id } ])
  end

  it "treats a processing document with no timestamp at all as stale" do
    document = build_document(status: "processing")

    reconciled = Documents::ReconcileStaleProcessingDocumentsService.call(stale_after: 30.minutes)

    expect(reconciled).to eq([ { document_id: document.id } ])
  end

  it "ignores documents that are not in processing status" do
    build_document(status: "failed", processing_last_attempt_at: 1.hour.ago)
    build_document(status: "completed", processing_last_attempt_at: 1.hour.ago)

    reconciled = Documents::ReconcileStaleProcessingDocumentsService.call(stale_after: 30.minutes)

    expect(reconciled).to be_empty
  end
end
