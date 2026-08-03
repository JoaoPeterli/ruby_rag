module Documents
  class IngestionJob < ApplicationJob
    queue_as :document_ingestion

    # Falhas desconhecidas recebem poucas tentativas.
    retry_on(
      StandardError,
      wait: :polynomially_longer,
      attempts: 3
    ) do |job, error|
      job.handle_final_failure(error)
    end

    # Rate limit costuma ser temporário.
    retry_on(
      Ai::EmbeddingService::RateLimitError,
      wait: :polynomially_longer,
      attempts: 8
    ) do |job, error|
      job.handle_final_failure(error)
    end

    # Timeouts e indisponibilidade temporária.
    retry_on(
      Ai::EmbeddingService::TimeoutError,
      Ai::EmbeddingService::TemporaryError,
      wait: :polynomially_longer,
      attempts: 5
    ) do |job, error|
      job.handle_final_failure(error)
    end

    # Não adianta repetir entradas inválidas ou autenticação incorreta.
    discard_on(
      Ai::EmbeddingService::AuthenticationError,
      Ai::EmbeddingService::InvalidRequestError,
      Ai::EmbeddingService::InvalidResponseError,
      Documents::IngestionService::InvalidDocumentError,
      Documents::IngestionService::EmptyTextError,
      Documents::ProcessingGuard::InvalidStatusError
    ) do |job, error|
      job.handle_final_failure(error)
    end

    # Um Job antigo não pode alterar uma execução nova.
    discard_on(
      Documents::ProcessingGuard::StaleRunError
    ) do |job, error|
      job.log_stale_job(error)
    end

    discard_on ActiveJob::DeserializationError

    def perform(document_id, run_id)
      started_at = Process.clock_gettime(
        Process::CLOCK_MONOTONIC
      )

      document = Document.find(document_id)

      Documents::ProcessingGuard.call(
        document: document,
        run_id: run_id
      )

      result = Documents::IngestionService.call(
        document: document,
        text: document.content,
        run_id: run_id
      )

      duration_ms = elapsed_milliseconds(started_at)

      Rails.logger.info(
        event: "document_ingestion_job_completed",
        document_id: document.id,
        run_id: run_id,
        chunks_count: result[:chunks_count],
        duration_ms: duration_ms
      )

      result
    end

    def handle_final_failure(error)
      document_id, run_id = arguments

      Documents::FailureStateService.call(
        document_id: document_id,
        run_id: run_id,
        error: error
      )
    end

    def log_stale_job(error)
      document_id, run_id = arguments

      Rails.logger.warn(
        event: "stale_document_ingestion_job_discarded",
        document_id: document_id,
        run_id: run_id,
        error_class: error.class.name,
        error_message: error.message
      )
    end

    private

    def elapsed_milliseconds(started_at)
      finished_at = Process.clock_gettime(
        Process::CLOCK_MONOTONIC
      )

      ((finished_at - started_at) * 1_000).round
    end
  end
end
