require "rails_helper"

RSpec.describe Documents::OcrExtractionJob do
  let(:run_id) { SecureRandom.uuid }
  let(:document) do
    create(
      :document,
      status: "uploaded",
      content: nil,
      metadata: { "ocr_run_id" => run_id }
    )
  end

  def stub_ocr_result(text: "Texto extraído do documento.", engine: "pdf_text_layer")
    result = Documents::OcrService::Result.new(text: text, engine: engine, duration_ms: 12.5)
    allow(Documents::OcrService).to receive(:call).and_return(result)
  end

  it "extracts the text and enqueues ingestion (which moves the document to queued)" do
    stub_ocr_result

    stub_ingestion_job_enqueue do
      Documents::OcrExtractionJob.new(document.id, run_id).perform(document.id, run_id)
    end

    document.reload
    expect(document.status).to eq("queued")
    expect(document.content).to eq("Texto extraído do documento.")
    expect(document.metadata["ocr_engine"]).to eq("pdf_text_layer")
    expect(document.metadata["ocr_completed_at"]).to be_present
  end

  it "raises StaleRunError when the document has moved on to a newer run" do
    document.update!(metadata: document.metadata.merge("ocr_run_id" => SecureRandom.uuid))
    stub_ocr_result

    expect do
      Documents::OcrExtractionJob.new(document.id, run_id).perform(document.id, run_id)
    end.to raise_error(Documents::OcrExtractionJob::StaleRunError)
  end

  it "propagates an unsupported file error from OcrService" do
    allow(Documents::OcrService).to receive(:call).and_raise(
      Documents::OcrService::UnsupportedFileError, "tipo não suportado"
    )

    expect do
      Documents::OcrExtractionJob.new(document.id, run_id).perform(document.id, run_id)
    end.to raise_error(Documents::OcrService::UnsupportedFileError)
  end

  describe "#handle_final_failure" do
    it "marks the document as failed when the run is still current" do
      job = Documents::OcrExtractionJob.new(document.id, run_id)

      job.handle_final_failure(Documents::OcrService::ExtractionError.new("falhou de vez"))

      document.reload
      expect(document.status).to eq("failed")
      expect(document.metadata["ocr_error_class"]).to eq("Documents::OcrService::ExtractionError")
      expect(document.metadata["ocr_error"]).to eq("falhou de vez")
    end

    it "does nothing when a stale job's run has already been superseded" do
      document.update!(metadata: document.metadata.merge("ocr_run_id" => SecureRandom.uuid))
      job = Documents::OcrExtractionJob.new(document.id, run_id)

      job.handle_final_failure(StandardError.new("erro antigo"))

      expect(document.reload.status).to eq("uploaded")
    end
  end

  describe "#log_stale_job" do
    it "does not raise" do
      job = Documents::OcrExtractionJob.new(document.id, run_id)

      expect { job.log_stale_job(Documents::OcrExtractionJob::StaleRunError.new("velho")) }.not_to raise_error
    end
  end
end
