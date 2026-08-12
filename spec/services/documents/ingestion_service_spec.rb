require "rails_helper"

RSpec.describe Documents::IngestionService do
  let(:account) { create(:account) }

  def build_document(run_id:, status: "processing")
    create(:document, status: status, account: account, metadata: { "ingestion_run_id" => run_id })
  end

  # Ai::BatchEmbeddingService não é injetável por DI no IngestionService,
  # então stubamos o método de classe em vez de deixar o caminho feliz sem
  # cobertura. O fake devolve um embedding por texto recebido, então se
  # adapta à quantidade de chunks que o pipeline de chunking real produzir
  # para o texto de teste.
  def stub_embeddings
    allow(Ai::BatchEmbeddingService).to receive(:call) do |texts:, **_kwargs|
      Ai::BatchEmbeddingService::Result.new(
        embeddings: Array.new(texts.size) { Array.new(1536, 0.01) },
        texts_count: texts.size,
        requests_count: 1,
        batch_size: texts.size,
        duration_ms: 1.0
      )
    end
  end

  it "raises for a document that has not been persisted" do
    expect do
      Documents::IngestionService.call(document: Document.new, text: "texto", run_id: "run-1")
    end.to raise_error(Documents::IngestionService::InvalidDocumentError)
  end

  it "raises for blank text" do
    document = build_document(run_id: "run-1")

    expect do
      Documents::IngestionService.call(document: document, text: "   ", run_id: "run-1")
    end.to raise_error(Documents::IngestionService::EmptyTextError)
  end

  it "raises for a blank run_id" do
    document = build_document(run_id: "run-1")

    expect do
      Documents::IngestionService.call(document: document, text: "texto", run_id: "  ")
    end.to raise_error(Documents::IngestionService::StaleRunError)
  end

  it "raises when packing_tokens plus overlap_tokens exceeds max_tokens" do
    document = build_document(run_id: "run-1")

    expect do
      Documents::IngestionService.call(
        document: document, text: "texto", run_id: "run-1",
        packing_tokens: 400, overlap_tokens: 200, max_tokens: 500
      )
    end.to raise_error(ArgumentError)
  end

  it "raises StaleRunError when the document's recorded run_id no longer matches" do
    document = build_document(run_id: "run-antigo")

    expect do
      Documents::IngestionService.call(document: document, text: "texto novo", run_id: "run-novo")
    end.to raise_error(Documents::IngestionService::StaleRunError)
  end

  it "raises when the document is not in processing status" do
    document = build_document(run_id: "run-1", status: "completed")
    stub_embeddings

    expect do
      Documents::IngestionService.call(document: document, text: "Um texto de teste qualquer.", run_id: "run-1")
    end.to raise_error(Documents::IngestionService::Error)
  end

  it "ingests the text into persisted chunks with embeddings and marks the document completed" do
    document = build_document(run_id: "run-1")
    stub_embeddings

    result = Documents::IngestionService.call(
      document: document,
      text: "Este é um texto de teste com conteúdo suficiente para gerar ao menos um chunk.",
      run_id: "run-1"
    )

    expect(result[:status]).to eq("completed")
    expect(result[:chunks_count]).to be > 0
    expect(document.document_chunks.count).to eq(result[:chunks_count])

    document.document_chunks.each do |chunk|
      point = Ai::VectorStoreService.default.retrieve(
        collection: Ai::Configuration::QDRANT_DOCUMENT_CHUNKS_COLLECTION,
        ids: [ chunk.id ]
      ).first

      expect(point).to be_present, "esperava um vetor no Qdrant para o chunk #{chunk.id}"
      expect(point.vector.size).to eq(1536)
    end

    expect(document.metadata["ingestion_run_id"]).to eq("run-1")
    expect(document.metadata["chunking_strategy"]).to eq("recursive_token_overlap")
  end
end
