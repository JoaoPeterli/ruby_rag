# frozen_string_literal: true

module Documents
  # Facade fina: monta a configuração (Config) e o contexto mutável
  # (Documents::Pipeline::AnswerContext), delega a execução real pra um
  # Documents::Pipeline::Pipeline de Steps (mesmo padrão já usado pelo
  # retrieval em Documents::RetrievalPipelineService::STEPS) e só cuida
  # do que é genuinamente transversal: validação de erro/log no nível
  # da requisição inteira.
  class QuestionAnsweringService
    DEFAULT_SEARCH_LIMIT = 5
    DEFAULT_CANDIDATE_LIMIT = 20
    DEFAULT_MINIMUM_SIMILARITY = 0.30
    DEFAULT_MMR_LAMBDA = 0.70
    DEFAULT_CITATION_ENGINE_ENABLED = true
    DEFAULT_GROUNDEDNESS_CHECK_ENABLED = true
    DEFAULT_HALLUCINATION_CHECK_ENABLED = false
    DEFAULT_CONFIDENCE_SCORE_ENABLED = true
    DEFAULT_PERSIST_ENABLED = true

    # Desligadas por padrão porque mudam comportamento de forma real
    # (cache pode reaproveitar resposta de pergunta "parecida mas
    # diferente"; budget muda o tamanho do contexto enviado; adaptive
    # retrieval e query router decidem sozinhos quais etapas rodar).
    DEFAULT_SEMANTIC_CACHE_ENABLED = false
    DEFAULT_SEMANTIC_CACHE_MINIMUM_SIMILARITY =
      Documents::SemanticCacheLookupService::DEFAULT_MINIMUM_SIMILARITY
    DEFAULT_SEMANTIC_CACHE_TTL =
      Documents::SemanticCacheStoreService::DEFAULT_TTL

    DEFAULT_TOKEN_BUDGET_ENABLED = false
    DEFAULT_TOKEN_BUDGET_TOTAL =
      Documents::TokenBudgetService::DEFAULT_TOTAL_BUDGET
    DEFAULT_TOKEN_BUDGET_RESPONSE_RESERVE =
      Documents::TokenBudgetService::DEFAULT_RESPONSE_RESERVE
    DEFAULT_TOKEN_BUDGET_SYSTEM_PROMPT_RESERVE =
      Documents::TokenBudgetService::DEFAULT_SYSTEM_PROMPT_RESERVE

    DEFAULT_ADAPTIVE_RETRIEVAL_ENABLED = false
    DEFAULT_QUERY_ROUTER_ENABLED = false

    # Só tem efeito quando conversation_history é passado, então é
    # seguro manter ligado por padrão — quem não usa conversa não é
    # afetado.
    DEFAULT_QUERY_REWRITE_ENABLED = true

    NO_EVIDENCE_ANSWER =
      "Não encontrei informações suficientes nas fontes fornecidas " \
      "para responder a esta pergunta."

    Source = Data.define(
      :chunk_id,
      :document_id,
      :content,
      :position,
      :original_position,
      :vector_position,
      :text_position,
      :distance,
      :similarity,
      :text_score,
      :normalized_text_score,
      :hybrid_score,
      :multi_query_score,
      :matched_queries,
      :query_match_count,
      :best_query_position,
      :rerank_score,
      :lexical_score,
      :matched_terms,
      :cross_encoder_score,
      :cross_encoder_reason,
      :combined_score,
      :mmr_score,
      :redundancy_score,
      :context_chunk_ids,
      :cited
    )

    Result = Data.define(
      :question,
      :effective_question,
      :answer,
      :sources,
      :search_query,
      :model,
      :finish_reason,
      :usage,
      :prompt_tokens,
      :completion_tokens,
      :total_tokens,
      :citations,
      :citation_coverage,
      :grounded,
      :refused,
      :hallucination_check,
      :confidence_score,
      :confidence_level,
      :cache_hit,
      :cache_similarity,
      :query_expansion_duration_ms,
      :retrieval_duration_ms,
      :duration_ms,
      :rag_query_id,
      :rag_answer_id
    )

    # Agrupa todos os "knobs" de configuração (flags de feature e DI de
    # colaboradores) num único value object, em vez de 40+ ivars soltas
    # na instância — quem quer saber o que um Step usa só olha o que
    # ele lê de context.config.
    Config = Data.define(
      :search_limit,
      :candidate_limit,
      :minimum_similarity,
      :mmr_lambda,
      :query_expansion_enabled,
      :multi_query_enabled,
      :metadata_extraction_enabled,
      :cross_encoder_enabled,
      :parent_retrieval_enabled,
      :context_compression_enabled,
      :citation_engine_enabled,
      :groundedness_check_enabled,
      :hallucination_check_enabled,
      :confidence_score_enabled,
      :persist_enabled,
      :semantic_cache_enabled,
      :semantic_cache_minimum_similarity,
      :semantic_cache_ttl,
      :token_budget_enabled,
      :token_budget_total,
      :token_budget_response_reserve,
      :token_budget_system_prompt_reserve,
      :adaptive_retrieval_enabled,
      :query_router_enabled,
      :query_rewrite_enabled,
      :retrieval_pipeline,
      :context_builder,
      :prompt_builder,
      :chat_completion_service,
      :chat_stream_service,
      :citation_engine,
      :groundedness_check_service,
      :hallucination_check_service,
      :confidence_score_service,
      :persistence_service,
      :embedding_service,
      :semantic_cache_lookup_service,
      :semantic_cache_store_service,
      :token_budget_service,
      :adaptive_retrieval_planner,
      :query_router_service,
      :query_rewrite_service
    )

    class Error < StandardError; end
    class InvalidQuestionError < Error; end
    class RetrievalError < Error; end
    class ContextBuildError < Error; end
    class PromptBuildError < Error; end
    class AnswerGenerationError < Error; end

    STEPS = [
      Documents::Pipeline::Steps::Answering::ValidateQuestionStep,
      Documents::Pipeline::Steps::Answering::ResolveEffectiveQuestionStep,
      Documents::Pipeline::Steps::Answering::SemanticCacheLookupStep,
      Documents::Pipeline::Steps::Answering::RouteQueryStep,
      Documents::Pipeline::Steps::Answering::AdaptiveRetrievalPlanStep,
      Documents::Pipeline::Steps::Answering::RetrieveDocumentsStep,
      Documents::Pipeline::Steps::Answering::TokenBudgetStep,
      Documents::Pipeline::Steps::Answering::BuildContextStep,
      Documents::Pipeline::Steps::Answering::BuildPromptStep,
      Documents::Pipeline::Steps::Answering::GenerateAnswerStep,
      Documents::Pipeline::Steps::Answering::BuildCitationsStep,
      Documents::Pipeline::Steps::Answering::CheckGroundednessStep,
      Documents::Pipeline::Steps::Answering::CheckHallucinationStep,
      Documents::Pipeline::Steps::Answering::CalculateConfidenceStep,
      Documents::Pipeline::Steps::Answering::BuildResultStep,
      Documents::Pipeline::Steps::Answering::StoreCacheStep,
      Documents::Pipeline::Steps::Answering::PersistStep
    ].freeze

    # Não usa o forwarding "(...)" comum porque aqui precisamos separar
    # o bloco (vai para #call, como callback de streaming) dos demais
    # argumentos (vão para #initialize).
    def self.call(*args, **kwargs, &on_delta)
      new(*args, **kwargs).call(&on_delta)
    end

    def initialize(
      question:,
      account_id: nil,
      conversation_history: [],
      search_limit: DEFAULT_SEARCH_LIMIT,
      candidate_limit: DEFAULT_CANDIDATE_LIMIT,
      minimum_similarity: DEFAULT_MINIMUM_SIMILARITY,
      mmr_lambda: DEFAULT_MMR_LAMBDA,
      query_expansion_enabled: nil,
      multi_query_enabled: nil,
      metadata_extraction_enabled: nil,
      cross_encoder_enabled: nil,
      parent_retrieval_enabled: nil,
      context_compression_enabled: nil,
      citation_engine_enabled: DEFAULT_CITATION_ENGINE_ENABLED,
      groundedness_check_enabled: DEFAULT_GROUNDEDNESS_CHECK_ENABLED,
      hallucination_check_enabled: DEFAULT_HALLUCINATION_CHECK_ENABLED,
      confidence_score_enabled: DEFAULT_CONFIDENCE_SCORE_ENABLED,
      persist_enabled: DEFAULT_PERSIST_ENABLED,
      semantic_cache_enabled: DEFAULT_SEMANTIC_CACHE_ENABLED,
      semantic_cache_minimum_similarity:
        DEFAULT_SEMANTIC_CACHE_MINIMUM_SIMILARITY,
      semantic_cache_ttl: DEFAULT_SEMANTIC_CACHE_TTL,
      token_budget_enabled: DEFAULT_TOKEN_BUDGET_ENABLED,
      token_budget_total: DEFAULT_TOKEN_BUDGET_TOTAL,
      token_budget_response_reserve: DEFAULT_TOKEN_BUDGET_RESPONSE_RESERVE,
      token_budget_system_prompt_reserve:
        DEFAULT_TOKEN_BUDGET_SYSTEM_PROMPT_RESERVE,
      adaptive_retrieval_enabled: DEFAULT_ADAPTIVE_RETRIEVAL_ENABLED,
      query_router_enabled: DEFAULT_QUERY_ROUTER_ENABLED,
      query_rewrite_enabled: DEFAULT_QUERY_REWRITE_ENABLED,
      retrieval_pipeline: Documents::RetrievalPipelineService,
      context_builder: Documents::ContextBuilder,
      prompt_builder: Documents::PromptBuilder,
      chat_completion_service: Ai::ChatCompletionService,
      chat_stream_service: Ai::ChatCompletionStreamService,
      citation_engine: Documents::CitationEngine::Service,
      groundedness_check_service: Documents::GroundednessCheckService,
      hallucination_check_service: Documents::HallucinationCheckService,
      confidence_score_service: Documents::ConfidenceScoreService,
      persistence_service: Documents::RagPersistenceService,
      embedding_service: Ai::EmbeddingService,
      semantic_cache_lookup_service: Documents::SemanticCacheLookupService,
      semantic_cache_store_service: Documents::SemanticCacheStoreService,
      token_budget_service: Documents::TokenBudgetService,
      adaptive_retrieval_planner: Documents::AdaptiveRetrievalPlanner,
      query_router_service: Documents::QueryRouterService,
      query_rewrite_service: Documents::QueryRewriteService
    )
      @question = question
      @account_id = account_id
      @conversation_history = Array(conversation_history)
      @config = Config.new(
        search_limit: search_limit,
        candidate_limit: candidate_limit,
        minimum_similarity: minimum_similarity,
        mmr_lambda: mmr_lambda,
        query_expansion_enabled: query_expansion_enabled,
        multi_query_enabled: multi_query_enabled,
        metadata_extraction_enabled: metadata_extraction_enabled,
        cross_encoder_enabled: cross_encoder_enabled,
        parent_retrieval_enabled: parent_retrieval_enabled,
        context_compression_enabled: context_compression_enabled,
        citation_engine_enabled: citation_engine_enabled,
        groundedness_check_enabled: groundedness_check_enabled,
        hallucination_check_enabled: hallucination_check_enabled,
        confidence_score_enabled: confidence_score_enabled,
        persist_enabled: persist_enabled,
        semantic_cache_enabled: semantic_cache_enabled,
        semantic_cache_minimum_similarity: semantic_cache_minimum_similarity,
        semantic_cache_ttl: semantic_cache_ttl,
        token_budget_enabled: token_budget_enabled,
        token_budget_total: token_budget_total,
        token_budget_response_reserve: token_budget_response_reserve,
        token_budget_system_prompt_reserve: token_budget_system_prompt_reserve,
        adaptive_retrieval_enabled: adaptive_retrieval_enabled,
        query_router_enabled: query_router_enabled,
        query_rewrite_enabled: query_rewrite_enabled,
        retrieval_pipeline: retrieval_pipeline,
        context_builder: context_builder,
        prompt_builder: prompt_builder,
        chat_completion_service: chat_completion_service,
        chat_stream_service: chat_stream_service,
        citation_engine: citation_engine,
        groundedness_check_service: groundedness_check_service,
        hallucination_check_service: hallucination_check_service,
        confidence_score_service: confidence_score_service,
        persistence_service: persistence_service,
        embedding_service: embedding_service,
        semantic_cache_lookup_service: semantic_cache_lookup_service,
        semantic_cache_store_service: semantic_cache_store_service,
        token_budget_service: token_budget_service,
        adaptive_retrieval_planner: adaptive_retrieval_planner,
        query_router_service: query_router_service,
        query_rewrite_service: query_rewrite_service
      )
    end

    def call(&on_delta)
      started_at = monotonic_time

      context = Documents::Pipeline::AnswerContext.new(
        question: question,
        account_id: account_id,
        conversation_history: conversation_history,
        config: config,
        on_delta: on_delta,
        started_at: started_at
      )

      Documents::Pipeline::Pipeline.call(context: context, steps: STEPS)

      log_success(context.result)

      context.result
    rescue Error => error
      log_failure(
        error: error,
        started_at: started_at
      )

      raise
    rescue StandardError => error
      wrapped_error = Error.new(
        "Não foi possível responder à pergunta: #{error.message}"
      )

      log_failure(
        error: wrapped_error,
        started_at: started_at,
        original_error: error
      )

      raise wrapped_error
    end

    private

    attr_reader :question, :account_id, :conversation_history, :config

    def log_success(result)
      Rails.logger.info(
        event: "document_question_answering_completed",
        question: result.question,
        model: result.model,
        sources_count: result.sources.size,
        prompt_tokens: result.prompt_tokens,
        completion_tokens: result.completion_tokens,
        total_tokens: result.total_tokens,
        citation_coverage: result.citation_coverage,
        grounded: result.grounded,
        refused: result.refused,
        confidence_score: result.confidence_score,
        confidence_level: result.confidence_level,
        cache_hit: result.cache_hit,
        retrieval_duration_ms: result.retrieval_duration_ms,
        duration_ms: result.duration_ms
      )
    end

    def log_failure(error:, started_at:, original_error: nil)
      Rails.logger.error(
        event: "document_question_answering_failed",
        error_class: error.class.name,
        error_message: error.message,
        original_error_class: original_error&.class&.name,
        original_error_message: original_error&.message,
        duration_ms: elapsed_milliseconds(started_at)
      )
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def elapsed_milliseconds(started_at)
      return 0 unless started_at

      finished_at = monotonic_time

      ((finished_at - started_at) * 1_000).round
    end
  end
end
