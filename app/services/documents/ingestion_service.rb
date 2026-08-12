module Documents
  class IngestionService
    DEFAULT_PACKING_TOKENS = 425
    DEFAULT_OVERLAP_TOKENS = 75
    DEFAULT_MAX_TOKENS = 500

    class Error < StandardError; end
    class InvalidDocumentError < Error; end
    class EmptyTextError < Error; end
    class StaleRunError < Error; end

    def self.call(
      document:,
      text:,
      run_id:,
      packing_tokens: DEFAULT_PACKING_TOKENS,
      overlap_tokens: DEFAULT_OVERLAP_TOKENS,
      max_tokens: DEFAULT_MAX_TOKENS,
      vector_store: Ai::VectorStoreService.default
    )
      new(
        document: document,
        text: text,
        run_id: run_id,
        packing_tokens: packing_tokens,
        overlap_tokens: overlap_tokens,
        max_tokens: max_tokens,
        vector_store: vector_store
      ).call
    end

    def initialize(
      document:,
      text:,
      run_id:,
      packing_tokens:,
      overlap_tokens:,
      max_tokens:,
      vector_store: Ai::VectorStoreService.default
    )
      @document = document
      @text = text.to_s
      @run_id = run_id
      @packing_tokens = packing_tokens
      @overlap_tokens = overlap_tokens
      @max_tokens = max_tokens
      @vector_store = vector_store
    end

    def call
      validate!

      started_at = Process.clock_gettime(
        Process::CLOCK_MONOTONIC
      )

      final_chunks = build_final_chunks

      embedding_result =
        generate_embeddings(final_chunks)

      validate_embeddings_count!(
        final_chunks,
        embedding_result.embeddings
      )

      attributes =
        build_chunk_attributes(final_chunks)

      persisted_chunks = persist_chunks!(attributes)

      upsert_vectors!(
        persisted_chunks,
        embedding_result.embeddings
      )

      mark_as_completed!(
        final_chunks,
        embedding_result,
        started_at
      )

      {
        document: document.reload,
        chunks_count: final_chunks.count,
        embedding_requests: embedding_result.requests_count,
        status: document.status
      }
    end

    private

    attr_reader :document,
                :text,
                :run_id,
                :packing_tokens,
                :overlap_tokens,
                :max_tokens,
                :vector_store

    def validate!
      unless document.is_a?(Document) && document.persisted?
        raise InvalidDocumentError,
              "Era esperado um Document persistido."
      end

      if text.strip.empty?
        raise EmptyTextError,
              "O texto do documento não pode estar vazio."
      end

      if run_id.to_s.strip.empty?
        raise StaleRunError,
              "O run_id não foi informado."
      end

      validate_token_configuration!
      ensure_current_run!
    end

    def validate_token_configuration!
      unless packing_tokens.is_a?(Integer) &&
             packing_tokens.positive?
        raise ArgumentError,
              "packing_tokens precisa ser um inteiro maior que zero."
      end

      unless overlap_tokens.is_a?(Integer) &&
             overlap_tokens >= 0
        raise ArgumentError,
              "overlap_tokens precisa ser um inteiro não negativo."
      end

      unless max_tokens.is_a?(Integer) &&
             max_tokens.positive?
        raise ArgumentError,
              "max_tokens precisa ser um inteiro maior que zero."
      end

      if packing_tokens + overlap_tokens > max_tokens
        raise ArgumentError,
              "packing_tokens + overlap_tokens não pode " \
              "ultrapassar max_tokens."
      end
    end

    def build_final_chunks
      recursive_chunks =
        Documents::RecursiveChunker.call(text)

      packed_chunks =
        Documents::PackingService.call(
          recursive_chunks,
          max_tokens: packing_tokens
        )

      chunks_with_overlap =
        Documents::TokenOverlapService.call(
          packed_chunks,
          overlap_tokens: overlap_tokens
        )

      Documents::FinalChunkValidator.call(
        chunks_with_overlap,
        max_tokens: max_tokens
      )
    end

    def generate_embeddings(chunks)
      ensure_current_run!

      result =
        Ai::BatchEmbeddingService.call(
          texts: chunks
        )

      Rails.logger.info(
        event: "document_embeddings_generated",
        document_id: document.id,
        run_id: run_id,
        chunks_count: result.texts_count,
        batch_size: result.batch_size,
        requests_count: result.requests_count,
        duration_ms: result.duration_ms,
        model: Ai::Configuration::EMBEDDING_MODEL
      )

      result
    end

    def build_chunk_attributes(chunks)
      chunks.map.with_index do |content, position|
        {
          content: content,
          position: position,
          metadata: chunk_metadata(content)
        }
      end
    end

    def validate_embeddings_count!(chunks, embeddings)
      unless embeddings.is_a?(Array)
        raise Error,
              "O serviço de embeddings não retornou um Array."
      end

      return if chunks.length == embeddings.length

      raise Error,
            "A quantidade de chunks é diferente da quantidade " \
            "de embeddings. Chunks: #{chunks.length}; " \
            "embeddings: #{embeddings.length}."
    end

    def chunk_metadata(content)
      injection_result = detect_prompt_injection(content)

      {
        "chunking_strategy" => "recursive_token_overlap",
        "token_count" => Ai::Tokenizer.count(content),
        "packing_tokens" => packing_tokens,
        "overlap_tokens" => overlap_tokens,
        "max_tokens" => max_tokens,
        "ingestion_run_id" => run_id,
        "prompt_injection_suspicious" => injection_result.suspicious,
        "prompt_injection_risk_score" => injection_result.risk_score
      }
    end

    def detect_prompt_injection(content)
      result = Documents::PromptInjectionDetectionService.call(content: content)

      if result.suspicious
        Rails.logger.warn(
          event: "document_chunk_prompt_injection_suspected",
          document_id: document.id,
          run_id: run_id,
          risk_score: result.risk_score,
          categories: result.matches.map(&:category).uniq
        )
      end

      result
    rescue Documents::PromptInjectionDetectionService::Error => error
      Rails.logger.warn(
        event: "document_chunk_prompt_injection_check_failed",
        document_id: document.id,
        run_id: run_id,
        error_class: error.class.name,
        error_message: error.message
      )

      Documents::PromptInjectionDetectionService::Result.new(
        suspicious: false,
        risk_score: 0.0,
        matches: []
      )
    end

    def persist_chunks!(attributes)
      document.with_lock do
        document.reload

        ensure_current_run!
        ensure_processing_status!

        DocumentChunk.transaction do
          document.document_chunks.delete_all

          # delete_all pula callbacks (after_destroy), então os pontos
          # antigos no Qdrant precisam ser apagados explicitamente aqui.
          vector_store.delete(
            collection: Ai::Configuration::QDRANT_DOCUMENT_CHUNKS_COLLECTION,
            filter: { document_id: document.id }
          )

          attributes.map do |chunk_attributes|
            document.document_chunks.create!(
              chunk_attributes
            )
          end
        end
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      raise Error,
            "Chunk duplicado detectado durante a ingestão do " \
            "documento #{document.id}: #{error.message}"
    end

    def upsert_vectors!(chunks, embeddings)
      points = chunks.zip(embeddings).map do |chunk, embedding|
        {
          id: chunk.id,
          vector: embedding,
          payload: {
            document_id: chunk.document_id,
            account_id: chunk.account_id,
            position: chunk.position
          }
        }
      end

      vector_store.upsert_batch(
        collection: Ai::Configuration::QDRANT_DOCUMENT_CHUNKS_COLLECTION,
        points: points
      )

      chunks.zip(embeddings).each do |chunk, embedding|
        chunk.embedding = embedding
      end
    end

    def mark_as_completed!(
      chunks,
      embedding_result,
      started_at
    )
      document.with_lock do
        document.reload

        ensure_current_run!
        ensure_processing_status!

        completed_at = Time.current.iso8601
        previous_ingested_hash =
          document.metadata.to_h["ingested_content_hash"]

        document.update!(
          status: "completed",
          content_version: next_content_version(previous_ingested_hash),
          metadata: cleaned_metadata.merge(
            "ingestion_run_id" => run_id,
            "chunking_strategy" =>
              "recursive_token_overlap",
            "chunks_count" => chunks.count,
            "packing_tokens" => packing_tokens,
            "overlap_tokens" => overlap_tokens,
            "max_tokens" => max_tokens,
            "embedding_model" =>
              Ai::Configuration::EMBEDDING_MODEL,
            "embedding_batch_size" =>
              embedding_result.batch_size,
            "embedding_requests" =>
              embedding_result.requests_count,
            "embedding_duration_ms" =>
              embedding_result.duration_ms,
            "indexed_at" => completed_at,
            "ingestion_completed_at" => completed_at,
            "ingestion_duration_ms" =>
              elapsed_milliseconds(started_at),
            "ingested_content_hash" => document.content_hash
          )
        )
      end
    end

    # Só conta como nova versão se já existia uma ingestão anterior com
    # hash diferente do atual — a primeira ingestão fica na versão 1.
    def next_content_version(previous_ingested_hash)
      return document.content_version if previous_ingested_hash.blank?
      return document.content_version if previous_ingested_hash == document.content_hash

      document.content_version + 1
    end

    def ensure_current_run!
      current_run_id =
        document
          .metadata
          .to_h["ingestion_run_id"]

      return if current_run_id == run_id

      raise StaleRunError,
            "A execução do documento foi substituída por outra."
    end

    def ensure_processing_status!
      return if document.status == "processing"

      raise Error,
            "O documento não está em processamento. " \
            "Status atual: #{document.status}."
    end

    def cleaned_metadata
      document
        .metadata
        .to_h
        .except(
          "ingestion_error",
          "ingestion_error_class",
          "ingestion_failed_at"
        )
    end

    def elapsed_milliseconds(started_at)
      finished_at = Process.clock_gettime(
        Process::CLOCK_MONOTONIC
      )

      ((finished_at - started_at) * 1_000).round
    end
  end
end
