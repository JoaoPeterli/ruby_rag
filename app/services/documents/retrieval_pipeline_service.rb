# frozen_string_literal: true

module Documents
  class RetrievalPipelineService
    DEFAULT_SEARCH_LIMIT = 5
    DEFAULT_CANDIDATE_LIMIT = 20
    DEFAULT_MINIMUM_SIMILARITY = 0.30
    DEFAULT_MMR_LAMBDA = 0.70
    DEFAULT_QUERY_EXPANSION_ENABLED = true
    DEFAULT_MULTI_QUERY_ENABLED = true
    DEFAULT_MULTI_QUERY_COUNT = 4
    DEFAULT_MULTI_QUERY_RESULT_LIMIT = 40
    DEFAULT_METADATA_EXTRACTION_ENABLED = true
    DEFAULT_PARENT_RETRIEVAL_ENABLED = true
    DEFAULT_PARENT_RETRIEVAL_WINDOW_SIZE =
      Documents::ParentDocumentRetrievalService::DEFAULT_WINDOW_SIZE
    DEFAULT_PARENT_RETRIEVAL_MAX_CHUNKS =
      Documents::ParentDocumentRetrievalService::DEFAULT_MAX_CHUNKS
    DEFAULT_CONTEXT_COMPRESSION_ENABLED = true
    DEFAULT_CONTEXT_COMPRESSION_MAX_CHUNKS =
      Documents::ContextCompression::SimilarityStrategy::DEFAULT_MAX_CHUNKS
    DEFAULT_CONTEXT_COMPRESSION_MINIMUM_SIMILARITY =
      Documents::ContextCompression::SimilarityStrategy::DEFAULT_MINIMUM_SIMILARITY
    DEFAULT_CONTEXT_COMPRESSION_PRESERVE_SOURCE_CHUNKS =
      Documents::ContextCompression::SimilarityStrategy::DEFAULT_PRESERVE_SOURCE_CHUNKS
    DEFAULT_CROSS_ENCODER_ENABLED = true
    DEFAULT_CROSS_ENCODER_CANDIDATE_LIMIT =
      Documents::CrossEncoder::Service::DEFAULT_CANDIDATE_LIMIT
    DEFAULT_CROSS_ENCODER_RERANK_LIMIT =
      Documents::CrossEncoder::Service::DEFAULT_RERANK_LIMIT
    DEFAULT_CROSS_ENCODER_MINIMUM_SCORE =
      Documents::CrossEncoder::Service::DEFAULT_MINIMUM_SCORE
    DEFAULT_CROSS_ENCODER_WEIGHT =
      Documents::CrossEncoder::Service::DEFAULT_CROSS_ENCODER_WEIGHT
    DEFAULT_CROSS_ENCODER_RETRIEVAL_WEIGHT =
      Documents::CrossEncoder::Service::DEFAULT_RETRIEVAL_WEIGHT
    DEFAULT_CROSS_ENCODER_BATCH_SIZE =
      Documents::CrossEncoder::LlmBatchStrategy::DEFAULT_BATCH_SIZE

    STEPS = [
      Documents::Pipeline::Steps::QueryExpansionStep,
      Documents::Pipeline::Steps::MultiQueryStep,
      Documents::Pipeline::Steps::MetadataExtractionStep,
      Documents::Pipeline::Steps::EmbeddingStep,
      Documents::Pipeline::Steps::HybridSearchStep,
      Documents::Pipeline::Steps::MergeStep,
      Documents::Pipeline::Steps::RerankStep,
      Documents::Pipeline::Steps::CrossEncoderRerankStep,
      Documents::Pipeline::Steps::MmrStep,
      Documents::Pipeline::Steps::ParentDocumentRetrievalStep,
      Documents::Pipeline::Steps::ContextCompressionStep
    ].freeze

    Result = Data.define(
      :results,
      :reranked_results,
      :cross_encoder_results,
      :cross_encoder,
      :context_chunks,
      :compressed_chunks,
      :parent_retrieval,
      :context_compression,
      :query_embedding,
      :original_question,
      :search_query,
      :queries,
      :query_expansion,
      :multi_query,
      :metadata_filters,
      :metrics,
      :stage_failures,
      :duration_ms
    )

    class Error < StandardError; end
    class InvalidQuestionError < Error; end
    class InvalidSearchLimitError < Error; end
    class InvalidCandidateLimitError < Error; end
    class InvalidMinimumSimilarityError < Error; end
    class InvalidMmrLambdaError < Error; end
    class NoRelevantResultsError < Error
      attr_reader(
        :search_query,
        :queries,
        :metrics,
        :stage_failures,
        :duration_ms
      )

      def initialize(
        message,
        search_query: nil,
        queries: [],
        metrics: {},
        stage_failures: [],
        duration_ms: nil
      )
        super(message)

        @search_query = search_query
        @queries = queries
        @metrics = metrics
        @stage_failures = stage_failures
        @duration_ms = duration_ms
      end
    end

    def self.call(...)
      new(...).call
    end

    def initialize(
      question:,
      search_limit: DEFAULT_SEARCH_LIMIT,
      candidate_limit: DEFAULT_CANDIDATE_LIMIT,
      minimum_similarity: DEFAULT_MINIMUM_SIMILARITY,
      mmr_lambda: DEFAULT_MMR_LAMBDA,
      query_expansion_enabled: DEFAULT_QUERY_EXPANSION_ENABLED,
      multi_query_enabled: DEFAULT_MULTI_QUERY_ENABLED,
      multi_query_count: DEFAULT_MULTI_QUERY_COUNT,
      multi_query_result_limit: DEFAULT_MULTI_QUERY_RESULT_LIMIT,
      metadata_extraction_enabled: DEFAULT_METADATA_EXTRACTION_ENABLED,
      parent_retrieval_enabled: DEFAULT_PARENT_RETRIEVAL_ENABLED,
      parent_retrieval_window_size: DEFAULT_PARENT_RETRIEVAL_WINDOW_SIZE,
      parent_retrieval_max_chunks: DEFAULT_PARENT_RETRIEVAL_MAX_CHUNKS,
      context_compression_enabled: DEFAULT_CONTEXT_COMPRESSION_ENABLED,
      context_compression_max_chunks: DEFAULT_CONTEXT_COMPRESSION_MAX_CHUNKS,
      context_compression_minimum_similarity:
        DEFAULT_CONTEXT_COMPRESSION_MINIMUM_SIMILARITY,
      context_compression_preserve_source_chunks:
        DEFAULT_CONTEXT_COMPRESSION_PRESERVE_SOURCE_CHUNKS,
      cross_encoder_enabled: DEFAULT_CROSS_ENCODER_ENABLED,
      cross_encoder_candidate_limit: DEFAULT_CROSS_ENCODER_CANDIDATE_LIMIT,
      cross_encoder_rerank_limit: DEFAULT_CROSS_ENCODER_RERANK_LIMIT,
      cross_encoder_minimum_score: DEFAULT_CROSS_ENCODER_MINIMUM_SCORE,
      cross_encoder_weight: DEFAULT_CROSS_ENCODER_WEIGHT,
      cross_encoder_retrieval_weight: DEFAULT_CROSS_ENCODER_RETRIEVAL_WEIGHT,
      cross_encoder_batch_size: DEFAULT_CROSS_ENCODER_BATCH_SIZE,
      account_id: nil,
      logger: Rails.logger
    )
      @question = question
      @account_id = account_id
      @search_limit = search_limit
      @candidate_limit = candidate_limit
      @minimum_similarity = minimum_similarity
      @mmr_lambda = mmr_lambda
      @query_expansion_enabled = query_expansion_enabled
      @multi_query_enabled = multi_query_enabled
      @multi_query_count = multi_query_count
      @multi_query_result_limit = multi_query_result_limit
      @metadata_extraction_enabled = metadata_extraction_enabled
      @parent_retrieval_enabled = parent_retrieval_enabled
      @parent_retrieval_window_size = parent_retrieval_window_size
      @parent_retrieval_max_chunks = parent_retrieval_max_chunks
      @context_compression_enabled = context_compression_enabled
      @context_compression_max_chunks = context_compression_max_chunks
      @context_compression_minimum_similarity =
        context_compression_minimum_similarity
      @context_compression_preserve_source_chunks =
        context_compression_preserve_source_chunks
      @cross_encoder_enabled = cross_encoder_enabled
      @cross_encoder_candidate_limit = cross_encoder_candidate_limit
      @cross_encoder_rerank_limit = cross_encoder_rerank_limit
      @cross_encoder_minimum_score = cross_encoder_minimum_score
      @cross_encoder_weight = cross_encoder_weight
      @cross_encoder_retrieval_weight = cross_encoder_retrieval_weight
      @cross_encoder_batch_size = cross_encoder_batch_size
      @logger = logger
    end

    def call
      started_at = monotonic_time

      validate!

      context = run_pipeline

      if context.results.blank?
        raise NoRelevantResultsError.new(
          "Nenhum conteúdo relevante foi encontrado para a pergunta",
          search_query: context.search_query,
          queries: context.queries,
          metrics: context.metrics,
          stage_failures: context.metadata[:stage_failures] || [],
          duration_ms: elapsed_ms(started_at)
        )
      end

      result = build_result(
        context: context,
        started_at: started_at
      )

      log_success(result, context)

      result
    rescue Error => error
      log_failure(
        error: error,
        started_at: started_at
      )

      raise
    rescue StandardError => error
      wrapped_error = Error.new(
        "Falha inesperada no pipeline de recuperação: #{error.message}"
      )

      log_failure(
        error: wrapped_error,
        original_error: error,
        started_at: started_at
      )

      raise wrapped_error
    end

    private

    attr_reader(
      :question,
      :search_limit,
      :candidate_limit,
      :minimum_similarity,
      :mmr_lambda,
      :query_expansion_enabled,
      :multi_query_enabled,
      :multi_query_count,
      :multi_query_result_limit,
      :metadata_extraction_enabled,
      :parent_retrieval_enabled,
      :parent_retrieval_window_size,
      :parent_retrieval_max_chunks,
      :context_compression_enabled,
      :context_compression_max_chunks,
      :context_compression_minimum_similarity,
      :context_compression_preserve_source_chunks,
      :cross_encoder_enabled,
      :cross_encoder_candidate_limit,
      :cross_encoder_rerank_limit,
      :cross_encoder_minimum_score,
      :cross_encoder_weight,
      :cross_encoder_retrieval_weight,
      :cross_encoder_batch_size,
      :account_id,
      :logger
    )

    def validate!
      validate_question!
      validate_search_limit!
      validate_candidate_limit!
      validate_minimum_similarity!
      validate_mmr_lambda!
    end

    def validate_question!
      return if question.is_a?(String) && question.strip.present?

      raise InvalidQuestionError,
            "A pergunta deve ser uma string não vazia"
    end

    def validate_search_limit!
      return if search_limit.is_a?(Integer) && search_limit.positive?

      raise InvalidSearchLimitError,
            "search_limit deve ser um inteiro maior que zero"
    end

    def validate_candidate_limit!
      valid =
        candidate_limit.is_a?(Integer) &&
        candidate_limit.positive? &&
        candidate_limit >= search_limit

      return if valid

      raise InvalidCandidateLimitError,
            "candidate_limit deve ser maior ou igual a search_limit"
    end

    def validate_minimum_similarity!
      valid =
        minimum_similarity.is_a?(Numeric) &&
        minimum_similarity.between?(0.0, 1.0)

      return if valid

      raise InvalidMinimumSimilarityError,
            "minimum_similarity deve estar entre 0 e 1"
    end

    def validate_mmr_lambda!
      valid =
        mmr_lambda.is_a?(Numeric) &&
        mmr_lambda.between?(0.0, 1.0)

      return if valid

      raise InvalidMmrLambdaError,
            "mmr_lambda deve estar entre 0 e 1"
    end

    def normalized_question
      @normalized_question ||= question.strip
    end

    def run_pipeline
      context = Documents::Pipeline::Context.new(
        question: normalized_question
      )

      context.metadata.merge!(
        search_limit: search_limit,
        candidate_limit: candidate_limit,
        minimum_similarity: minimum_similarity,
        mmr_lambda: mmr_lambda,
        query_expansion_enabled: query_expansion_enabled,
        multi_query_enabled: multi_query_enabled,
        multi_query_count: multi_query_count,
        multi_query_result_limit: multi_query_result_limit,
        metadata_extraction_enabled: metadata_extraction_enabled,
        parent_retrieval_enabled: parent_retrieval_enabled,
        parent_retrieval_window_size: parent_retrieval_window_size,
        parent_retrieval_max_chunks: parent_retrieval_max_chunks,
        context_compression_enabled: context_compression_enabled,
        context_compression_max_chunks: context_compression_max_chunks,
        context_compression_minimum_similarity:
          context_compression_minimum_similarity,
        context_compression_preserve_source_chunks:
          context_compression_preserve_source_chunks,
        cross_encoder_enabled: cross_encoder_enabled,
        cross_encoder_candidate_limit: cross_encoder_candidate_limit,
        cross_encoder_rerank_limit: cross_encoder_rerank_limit,
        cross_encoder_minimum_score: cross_encoder_minimum_score,
        cross_encoder_weight: cross_encoder_weight,
        cross_encoder_retrieval_weight: cross_encoder_retrieval_weight,
        cross_encoder_batch_size: cross_encoder_batch_size,
        account_id: account_id
      )

      Documents::Pipeline::Pipeline.call(
        context: context,
        steps: STEPS
      )
    end

    def build_result(context:, started_at:)
      Result.new(
        results: context.results,
        reranked_results: context.reranked_results,
        cross_encoder_results: context.cross_encoder_results,
        cross_encoder: context.cross_encoder,
        context_chunks: context.context_chunks,
        compressed_chunks: effective_compressed_chunks(context),
        parent_retrieval: context.parent_retrieval,
        context_compression: context.context_compression,
        query_embedding: resolve_query_embedding(context),
        original_question: context.question,
        search_query: context.search_query,
        queries: context.queries,
        query_expansion: context.expanded_query,
        multi_query: context.metadata[:multi_query],
        metadata_filters: context.metadata_filters,
        metrics: context.metrics,
        stage_failures: context.metadata[:stage_failures] || [],
        duration_ms: elapsed_ms(started_at)
      )
    end

    def effective_compressed_chunks(context)
      return context.compressed_chunks if context.compressed_chunks.present?
      return context.context_chunks if context.context_chunks.present?

      context.results.map(&:chunk)
    end

    def resolve_query_embedding(context)
      context.query_embeddings[context.question] ||
        context.query_embeddings[context.search_query] ||
        context.query_embeddings.values.first
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def elapsed_ms(started_at)
      ((monotonic_time - started_at) * 1_000).round(2)
    end

    def log_success(result, context)
      logger.info(
        {
          event: "retrieval_pipeline.success",
          question: normalized_question,
          search_query: result.search_query,
          queries_count: result.queries.size,
          metadata_filters: result.metadata_filters.to_h,
          results_count: result.results.size,
          context_chunks_count: result.context_chunks.size,
          compressed_chunks_count: result.compressed_chunks.size,
          cross_encoder_results_count: result.cross_encoder_results.size,
          metrics: context.metrics,
          duration_ms: result.duration_ms
        }.to_json
      )
    end

    def log_failure(error:, started_at:, original_error: nil)
      logger.error(
        {
          event: "retrieval_pipeline.failure",
          question: question,
          error_class: error.class.name,
          error_message: error.message,
          original_error_class: original_error&.class&.name,
          duration_ms: elapsed_ms(started_at)
        }.compact.to_json
      )
    end
  end
end
