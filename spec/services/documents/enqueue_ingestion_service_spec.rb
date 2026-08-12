require "rails_helper"

RSpec.describe Documents::EnqueueIngestionService do
  def build_document(status: "pending")
    create(:document, status: status)
  end

  def stub_enqueue
    fake_job = Struct.new(:job_id).new(SecureRandom.uuid)
    allow(Documents::IngestionJob).to receive(:perform_later).and_return(fake_job)
  end

  it "queues the document and stores ingestion metadata" do
    document = build_document
    stub_enqueue

    job = Documents::EnqueueIngestionService.call(document: document)

    expect(job).not_to be_nil
    document.reload
    expect(document.status).to eq("queued")
    expect(document.metadata["ingestion_run_id"]).to be_present
    expect(document.metadata["ingestion_attempts"]).to eq(0)
    expect(document.metadata["active_job_id"]).to be_present
  end

  it "returns nil without enqueuing when unchanged and already completed" do
    document = build_document(status: "completed")
    document.update!(status: "completed", metadata: { "ingested_content_hash" => document.content_hash })
    stub_enqueue

    result = Documents::EnqueueIngestionService.call(document: document)

    expect(result).to be_nil
    document.reload
    expect(document.status).to eq("completed")
  end

  it "forces re-enqueue even when unchanged, when force: true" do
    document = build_document(status: "completed")
    document.update!(status: "completed", metadata: { "ingested_content_hash" => document.content_hash })
    stub_enqueue

    job = Documents::EnqueueIngestionService.call(document: document, force: true)

    expect(job).not_to be_nil
    document.reload
    expect(document.status).to eq("queued")
  end

  it "raises for an unpersisted document" do
    expect do
      Documents::EnqueueIngestionService.call(document: Document.new)
    end.to raise_error(Documents::EnqueueIngestionService::InvalidDocumentError)
  end

  it "raises for a document without content" do
    document = build_document
    document.update_column(:content, "")

    expect do
      Documents::EnqueueIngestionService.call(document: document)
    end.to raise_error(Documents::EnqueueIngestionService::EmptyContentError)
  end

  it "raises when the document is already queued or processing" do
    document = build_document(status: "processing")

    expect do
      Documents::EnqueueIngestionService.call(document: document)
    end.to raise_error(Documents::EnqueueIngestionService::AlreadyScheduledError)
  end

  it "marks the document as failed when enqueuing raises unexpectedly" do
    document = build_document
    allow(Documents::IngestionJob).to receive(:perform_later).and_raise("job enqueue broke")

    expect do
      Documents::EnqueueIngestionService.call(document: document)
    end.to raise_error(Documents::EnqueueIngestionService::Error)

    document.reload
    expect(document.status).to eq("failed")
    expect(document.metadata["ingestion_error_class"]).to eq("RuntimeError")
  end
end
