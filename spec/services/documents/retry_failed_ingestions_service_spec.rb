require "rails_helper"

RSpec.describe Documents::RetryFailedIngestionsService do
  def job_double_class
    @job_double_class ||= Struct.new(:job_id)
  end

  def build_failed_document(account:, title: "Documento com falha")
    create(:document, title: title, status: "failed", account: account)
  end

  it "enqueues every document in scope and returns document/job id pairs" do
    account = create(:account)
    first = build_failed_document(account: account, title: "Documento 1")
    second = build_failed_document(account: account, title: "Documento 2")

    calls = []
    job_class = job_double_class
    enqueue_service = Class.new do
      define_singleton_method(:call) do |**kwargs|
        calls << kwargs
        job_class.new("job-#{kwargs[:document].id}")
      end
    end

    result = Documents::RetryFailedIngestionsService.call(
      scope: Document.where(id: [ first.id, second.id ]),
      enqueue_service: enqueue_service,
      logger: Logger.new(IO::NULL)
    )

    expect(calls.size).to eq(2)
    expect(calls.all? { |call| call[:force] }).to be_truthy
    expect(result).to eq(
      [ { document_id: first.id, job_id: "job-#{first.id}" }, { document_id: second.id, job_id: "job-#{second.id}" } ]
    )
  end

  it "skips documents that fail to enqueue but keeps processing the rest" do
    account = create(:account)
    failing = build_failed_document(account: account, title: "Falha ao enfileirar")
    succeeding = build_failed_document(account: account, title: "Enfileira normalmente")

    job_class = job_double_class
    enqueue_service = Class.new do
      define_singleton_method(:call) do |document:, force:|
        raise Documents::EnqueueIngestionService::Error, "fila indisponível" if document.title == "Falha ao enfileirar"

        job_class.new("job-#{document.id}")
      end
    end

    result = Documents::RetryFailedIngestionsService.call(
      scope: Document.where(id: [ failing.id, succeeding.id ]),
      enqueue_service: enqueue_service,
      logger: Logger.new(IO::NULL)
    )

    expect(result).to eq([ { document_id: succeeding.id, job_id: "job-#{succeeding.id}" } ])
  end

  it "does nothing when the scope is empty" do
    result = Documents::RetryFailedIngestionsService.call(
      scope: Document.where(id: -1),
      enqueue_service: Class.new { define_singleton_method(:call) { |**_kwargs| raise "não deveria ser chamado" } },
      logger: Logger.new(IO::NULL)
    )

    expect(result).to be_empty
  end
end
