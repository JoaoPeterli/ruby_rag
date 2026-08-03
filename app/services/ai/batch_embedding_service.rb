module Ai
  class BatchEmbeddingService
    class Error < StandardError; end
    class InvalidInputError < Error; end
    class ResultMismatchError < Error; end

    Result = Struct.new(
      :embeddings,
      :texts_count,
      :requests_count,
      :batch_size,
      :duration_ms,
      keyword_init: true
    )

    def self.call(
      texts:,
      batch_size: Ai::Configuration::EMBEDDING_BATCH_SIZE,
      embedding_service: Ai::EmbeddingService
    )
      new(
        texts: texts,
        batch_size: batch_size,
        embedding_service: embedding_service
      ).call
    end

    def initialize(texts:, batch_size:, embedding_service:)
      @texts = normalize_texts(texts)
      @batch_size = batch_size.to_i
      @embedding_service = embedding_service
    end

    def call
      validate!

      started_at = Process.clock_gettime(
        Process::CLOCK_MONOTONIC
      )

      embeddings = []
      requests_count = 0

      texts.each_slice(batch_size) do |batch|
        batch_embeddings = embedding_service.call(
          texts: batch
        )

        validate_batch_result!(
          batch: batch,
          embeddings: batch_embeddings
        )

        embeddings.concat(batch_embeddings)
        requests_count += 1
      end

      validate_final_result!(embeddings)

      finished_at = Process.clock_gettime(
        Process::CLOCK_MONOTONIC
      )

      Result.new(
        embeddings: embeddings,
        texts_count: texts.length,
        requests_count: requests_count,
        batch_size: batch_size,
        duration_ms: duration_in_ms(
          started_at,
          finished_at
        )
      )
    end

    private

    attr_reader :texts,
                :batch_size,
                :embedding_service

    def normalize_texts(value)
      Array(value).map do |text|
        text.to_s.strip
      end
    end

    def validate!
      if texts.empty?
        raise InvalidInputError,
              "É necessário informar pelo menos um texto."
      end

      if batch_size <= 0
        raise InvalidInputError,
              "O tamanho do lote deve ser maior que zero."
      end

      empty_position = texts.index(&:blank?)

      return unless empty_position

      raise InvalidInputError,
            "O texto da posição #{empty_position} está vazio."
    end

    def validate_batch_result!(batch:, embeddings:)
      unless embeddings.is_a?(Array)
        raise ResultMismatchError,
              "O serviço de embeddings não retornou um Array."
      end

      return if embeddings.length == batch.length

      raise ResultMismatchError,
            "O lote possui #{batch.length} textos, mas retornou " \
            "#{embeddings.length} embeddings."
    end

    def validate_final_result!(embeddings)
      return if embeddings.length == texts.length

      raise ResultMismatchError,
            "Foram enviados #{texts.length} textos, mas recebidos " \
            "#{embeddings.length} embeddings."
    end

    def duration_in_ms(started_at, finished_at)
      ((finished_at - started_at) * 1_000).round
    end
  end
end
