# frozen_string_literal: true

module Documents
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

    class Error < StandardError; end
    class InvalidQuestionError < Error; end
    class RetrievalError < Error; end
    class ContextBuildError < Error; end
    class PromptBuildError < Error; end
    class AnswerGenerationError < Error; end

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
      @search_limit = search_limit
      @candidate_limit = candidate_limit
      @minimum_similarity = minimum_similarity
      @mmr_lambda = mmr_lambda
      @query_expansion_enabled = query_expansion_enabled
      @multi_query_enabled = multi_query_enabled
      @metadata_extraction_enabled = metadata_extraction_enabled
      @cross_encoder_enabled = cross_encoder_enabled
      @parent_retrieval_enabled = parent_retrieval_enabled
      @context_compression_enabled = context_compression_enabled
      @citation_engine_enabled = citation_engine_enabled
      @groundedness_check_enabled = groundedness_check_enabled
      @hallucination_check_enabled = hallucination_check_enabled
      @confidence_score_enabled = confidence_score_enabled
      @persist_enabled = persist_enabled
      @semantic_cache_enabled = semantic_cache_enabled
      @semantic_cache_minimum_similarity = semantic_cache_minimum_similarity
      @semantic_cache_ttl = semantic_cache_ttl
      @token_budget_enabled = token_budget_enabled
      @token_budget_total = token_budget_total
      @token_budget_response_reserve = token_budget_response_reserve
      @token_budget_system_prompt_reserve = token_budget_system_prompt_reserve
      @adaptive_retrieval_enabled = adaptive_retrieval_enabled
      @query_router_enabled = query_router_enabled
      @query_rewrite_enabled = query_rewrite_enabled
      @retrieval_pipeline = retrieval_pipeline
      @context_builder = context_builder
      @prompt_builder = prompt_builder
      @chat_completion_service = chat_completion_service
      @chat_stream_service = chat_stream_service
      @citation_engine = citation_engine
      @groundedness_check_service = groundedness_check_service
      @hallucination_check_service = hallucination_check_service
      @confidence_score_service = confidence_score_service
      @persistence_service = persistence_service
      @embedding_service = embedding_service
      @semantic_cache_lookup_service = semantic_cache_lookup_service
      @semantic_cache_store_service = semantic_cache_store_service
      @token_budget_service = token_budget_service
      @adaptive_retrieval_planner = adaptive_retrieval_planner
      @query_router_service = query_router_service
      @query_rewrite_service = query_rewrite_service
    end

    def call(&on_delta)
      started_at = monotonic_time

      validate!

      resolve_effective_question

      cache_hit = lookup_cache

      if cache_hit
        result = build_cache_hit_result(
          cache_hit: cache_hit,
          started_at: started_at
        )

        result = persist(result: result, retrieval_result: nil)

        log_success(result)

        return result
      end

      retrieval_result = retrieve_documents

      context_result = build_context(retrieval_result)

      prompt = build_prompt(context_result)

      chat_result = generate_answer(prompt, &on_delta)

      citation_result = build_citations(
        chat_result: chat_result,
        context_result: context_result
      )

      groundedness_result = check_groundedness(
        chat_result: chat_result,
        citation_result: citation_result
      )

      hallucination_result = check_hallucination(
        chat_result: chat_result,
        context_result: context_result
      )

      confidence_result = calculate_confidence(
        retrieval_result: retrieval_result,
        citation_result: citation_result,
        groundedness_result: groundedness_result,
        hallucination_result: hallucination_result
      )

      result = build_result(
        chat_result: chat_result,
        retrieval_result: retrieval_result,
        citation_result: citation_result,
        groundedness_result: groundedness_result,
        hallucination_result: hallucination_result,
        confidence_result: confidence_result,
        started_at: started_at
      )

      store_cache(result: result)

      result = persist(
        result: result,
        retrieval_result: retrieval_result
      )

      log_success(result)

      result
    rescue Documents::RetrievalPipelineService::NoRelevantResultsError => error
      result = build_no_evidence_result(
        error: error,
        started_at: started_at
      )

      store_cache(result: result)

      result = persist(
        result: result,
        retrieval_result: nil
      )

      log_success(result)

      result
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

    attr_reader(
      :question,
      :account_id,
      :conversation_history,
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

    def validate!
      validate_question!
    end

    def validate_question!
      return if question.is_a?(String) && question.strip.present?

      raise InvalidQuestionError,
            "A pergunta deve ser uma string não vazia"
    end

    # --- Aulas 43-44: histórico da conversa + reescrita contextual ---

    def resolve_effective_question
      @query_rewrite_result = rewrite_question
      @effective_question =
        @query_rewrite_result&.rewritten_question || normalized_question
    end

    def effective_question
      @effective_question ||= normalized_question
    end

    def rewrite_question
      return unless query_rewrite_enabled && conversation_history.present?

      query_rewrite_service.call(
        question: normalized_question,
        history: conversation_history
      )
    rescue Documents::QueryRewriteService::Error => error
      log_stage_failure(stage: "query_rewrite", error: error)

      nil
    end

    # --- Aula 39: cache semântico ---

    def question_embedding
      return @question_embedding if defined?(@question_embedding)

      @question_embedding = compute_question_embedding
    end

    def compute_question_embedding
      return unless semantic_cache_enabled

      embeddings = embedding_service.call(texts: [ effective_question ])

      embeddings.is_a?(Array) ? embeddings.first : nil
    rescue Ai::EmbeddingService::Error => error
      log_stage_failure(stage: "semantic_cache_embedding", error: error)

      nil
    end

    def lookup_cache
      return unless semantic_cache_enabled && question_embedding

      semantic_cache_lookup_service.call(
        question_embedding: question_embedding,
        minimum_similarity: semantic_cache_minimum_similarity,
        scope: cache_scope
      )
    rescue Documents::SemanticCacheLookupService::Error => error
      log_stage_failure(stage: "semantic_cache_lookup", error: error)

      nil
    end

    def store_cache(result:)
      return unless semantic_cache_enabled && question_embedding

      semantic_cache_store_service.call(
        question: effective_question,
        question_embedding: question_embedding,
        qa_result: result,
        ttl: semantic_cache_ttl,
        account_id: account_id
      )
    rescue Documents::SemanticCacheStoreService::Error => error
      log_stage_failure(stage: "semantic_cache_store", error: error)

      nil
    end

    def cache_scope
      scope = RagSemanticCacheEntry.not_expired

      return scope if account_id.nil?

      scope.where(account_id: account_id)
    end

    # --- Aulas 41-42: adaptive retrieval + query router ---

    def route_query
      return unless query_router_enabled
      return @route_query if defined?(@route_query)

      @route_query = query_router_service.call(question: effective_question)
    rescue Documents::QueryRouterService::Error => error
      log_stage_failure(stage: "query_router", error: error)

      @route_query = nil
    end

    def adaptive_plan
      return unless adaptive_retrieval_enabled
      return @adaptive_plan if defined?(@adaptive_plan)

      @adaptive_plan = adaptive_retrieval_planner.call(
        question: effective_question,
        category: route_query&.category
      )
    rescue Documents::AdaptiveRetrievalPlanner::Error => error
      log_stage_failure(stage: "adaptive_retrieval_planner", error: error)

      @adaptive_plan = nil
    end

    def pipeline_overrides
      plan = adaptive_plan

      {
        query_expansion_enabled: query_expansion_enabled.nil? ? plan&.query_expansion_enabled : query_expansion_enabled,
        multi_query_enabled: multi_query_enabled.nil? ? plan&.multi_query_enabled : multi_query_enabled,
        metadata_extraction_enabled: metadata_extraction_enabled.nil? ? plan&.metadata_extraction_enabled : metadata_extraction_enabled,
        cross_encoder_enabled: cross_encoder_enabled.nil? ? plan&.cross_encoder_enabled : cross_encoder_enabled,
        parent_retrieval_enabled: parent_retrieval_enabled.nil? ? plan&.parent_retrieval_enabled : parent_retrieval_enabled,
        context_compression_enabled: context_compression_enabled.nil? ? plan&.context_compression_enabled : context_compression_enabled
      }.compact
    end

    def retrieve_documents
      retrieval_pipeline.call(
        question: effective_question,
        account_id: account_id,
        search_limit: search_limit,
        candidate_limit: candidate_limit,
        minimum_similarity: minimum_similarity,
        mmr_lambda: mmr_lambda,
        **pipeline_overrides
      )
    rescue Documents::RetrievalPipelineService::NoRelevantResultsError
      raise
    rescue Documents::RetrievalPipelineService::Error => error
      raise RetrievalError,
            "Não foi possível recuperar o contexto: #{error.message}"
    end

    # --- Aula 40: orçamento de tokens ---

    def token_budget
      return unless token_budget_enabled
      return @token_budget if defined?(@token_budget)

      @token_budget = token_budget_service.call(
        total_budget: token_budget_total,
        response_reserve: token_budget_response_reserve,
        system_prompt_reserve: token_budget_system_prompt_reserve
      )
    rescue Documents::TokenBudgetService::Error => error
      log_stage_failure(stage: "token_budget", error: error)

      @token_budget = nil
    end

    def response_token_budget
      token_budget&.response_budget_tokens ||
        Ai::Configuration.chat_max_completion_tokens
    end

    def build_context(retrieval_result)
      chunks = context_chunks_for(retrieval_result)

      results = to_vector_search_results(
        chunks: chunks,
        search_results: retrieval_result.results
      )

      budget = token_budget

      if budget
        context_builder.call(
          results: results,
          max_characters: budget.context_budget_characters
        )
      else
        context_builder.call(results: results)
      end
    rescue Documents::ContextBuilder::Error => error
      raise ContextBuildError,
            "Não foi possível construir o contexto: #{error.message}"
    end

    def context_chunks_for(retrieval_result)
      if retrieval_result.compressed_chunks.present?
        retrieval_result.compressed_chunks
      elsif retrieval_result.context_chunks.present?
        retrieval_result.context_chunks
      else
        retrieval_result.results.map(&:chunk)
      end
    end

    def to_vector_search_results(chunks:, search_results:)
      search_results_by_chunk_id =
        search_results.index_by { |search_result| search_result.chunk.id }

      chunks.map do |chunk|
        search_result = search_results_by_chunk_id[chunk.id]

        Documents::VectorSearchResult.new(
          chunk_id: chunk.id,
          document_id: chunk.document_id,
          content: chunk.content,
          position: chunk.position,
          distance: search_result&.distance,
          score: search_result&.similarity || 0.0,
          metadata: chunk.metadata.to_h
        )
      end
    end

    def build_prompt(context_result)
      prompt_builder.call(
        question: effective_question,
        context_result: context_result,
        conversation_history: conversation_history
      )
    rescue Documents::PromptBuilder::Error => error
      raise PromptBuildError,
            "Não foi possível construir o prompt: #{error.message}"
    end

    def generate_answer(prompt, &on_delta)
      if on_delta
        chat_stream_service.call(
          messages: prompt.messages,
          model: Ai::Configuration.chat_model,
          temperature: Ai::Configuration.chat_temperature,
          max_completion_tokens: response_token_budget,
          &on_delta
        )
      else
        chat_completion_service.call(
          messages: prompt.messages,
          model: Ai::Configuration.chat_model,
          temperature: Ai::Configuration.chat_temperature,
          max_completion_tokens: response_token_budget
        )
      end
    rescue Ai::ChatCompletionService::Error, Ai::ChatCompletionStreamService::Error => error
      raise AnswerGenerationError,
            "Não foi possível gerar a resposta: #{error.message}"
    end

    def build_citations(chat_result:, context_result:)
      return unless citation_engine_enabled

      citation_engine.call(
        answer: chat_result.content,
        sources: context_result.sources
      )
    rescue Documents::CitationEngine::Service::Error => error
      log_stage_failure(stage: "citation_engine", error: error)

      nil
    end

    def check_groundedness(chat_result:, citation_result:)
      return unless groundedness_check_enabled

      groundedness_check_service.call(
        answer: chat_result.content,
        citation_count: citation_result&.citation_count || 0
      )
    rescue Documents::GroundednessCheckService::Error => error
      log_stage_failure(stage: "groundedness_check", error: error)

      nil
    end

    def check_hallucination(chat_result:, context_result:)
      return unless hallucination_check_enabled

      hallucination_check_service.call(
        question: effective_question,
        answer: chat_result.content,
        context: context_result.context
      )
    rescue Documents::HallucinationCheckService::Error => error
      log_stage_failure(stage: "hallucination_check", error: error)

      nil
    end

    def calculate_confidence(
      retrieval_result:,
      citation_result:,
      groundedness_result:,
      hallucination_result:
    )
      return unless confidence_score_enabled

      confidence_score_service.call(
        retrieval_result: retrieval_result,
        citation_result: citation_result,
        groundedness_result: groundedness_result,
        hallucination_result: hallucination_result
      )
    rescue Documents::ConfidenceScoreService::Error => error
      log_stage_failure(stage: "confidence_score", error: error)

      nil
    end

    def persist(result:, retrieval_result:)
      return result unless persist_enabled

      rag_query = persistence_service.call(
        qa_result: result,
        retrieval_result: retrieval_result,
        account_id: account_id
      )

      result.with(
        rag_query_id: rag_query.id,
        rag_answer_id: rag_query.rag_answer&.id
      )
    rescue Documents::RagPersistenceService::Error => error
      log_stage_failure(stage: "persistence", error: error)

      result
    end

    def log_stage_failure(stage:, error:)
      Rails.logger.warn(
        event: "document_question_answering_stage_failure",
        stage: stage,
        error_class: error.class.name,
        error_message: error.message
      )
    end

    def build_result(
      chat_result:,
      retrieval_result:,
      citation_result:,
      groundedness_result:,
      hallucination_result:,
      confidence_result:,
      started_at:
    )
      Result.new(
        question: normalized_question,
        effective_question: effective_question,
        answer: chat_result.content,
        sources: build_sources(
          retrieval_result.results,
          parent_retrieval: retrieval_result.parent_retrieval,
          citation_result: citation_result
        ),
        search_query: retrieval_result.search_query,
        model: chat_result.model,
        finish_reason: chat_result.finish_reason,
        usage: chat_result.usage,
        prompt_tokens: chat_result.prompt_tokens,
        completion_tokens: chat_result.completion_tokens,
        total_tokens: chat_result.total_tokens,
        citations: citation_result&.citations || [],
        citation_coverage: citation_result&.citation_coverage,
        grounded: groundedness_result&.grounded,
        refused: groundedness_result&.refused,
        hallucination_check: hallucination_result,
        confidence_score: confidence_result&.score,
        confidence_level: confidence_result&.level,
        cache_hit: false,
        cache_similarity: nil,
        query_expansion_duration_ms:
          retrieval_result.query_expansion&.duration_ms,
        retrieval_duration_ms: retrieval_result.duration_ms,
        duration_ms: elapsed_milliseconds(started_at),
        rag_query_id: nil,
        rag_answer_id: nil
      )
    end

    def build_no_evidence_result(error:, started_at:)
      Result.new(
        question: normalized_question,
        effective_question: effective_question,
        answer: NO_EVIDENCE_ANSWER,
        sources: [],
        search_query: error.search_query,
        model: nil,
        finish_reason: nil,
        usage: nil,
        prompt_tokens: nil,
        completion_tokens: nil,
        total_tokens: nil,
        citations: [],
        citation_coverage: nil,
        grounded: true,
        refused: true,
        hallucination_check: nil,
        confidence_score: nil,
        confidence_level: nil,
        cache_hit: false,
        cache_similarity: nil,
        query_expansion_duration_ms: nil,
        retrieval_duration_ms: error.duration_ms,
        duration_ms: elapsed_milliseconds(started_at),
        rag_query_id: nil,
        rag_answer_id: nil
      )
    end

    def build_cache_hit_result(cache_hit:, started_at:)
      entry = cache_hit.entry

      Result.new(
        question: normalized_question,
        effective_question: effective_question,
        answer: entry.answer,
        sources: [],
        search_query: nil,
        model: entry.model,
        finish_reason: nil,
        usage: nil,
        prompt_tokens: nil,
        completion_tokens: nil,
        total_tokens: nil,
        citations: [],
        citation_coverage: nil,
        grounded: nil,
        refused: nil,
        hallucination_check: nil,
        confidence_score: entry.confidence_score,
        confidence_level: entry.confidence_level,
        cache_hit: true,
        cache_similarity: cache_hit.similarity,
        query_expansion_duration_ms: nil,
        retrieval_duration_ms: nil,
        duration_ms: elapsed_milliseconds(started_at),
        rag_query_id: nil,
        rag_answer_id: nil
      )
    end

    def build_sources(search_results, parent_retrieval: nil, citation_result: nil)
      cited_chunk_ids = citation_result&.cited_chunk_ids

      search_results.map do |search_result|
        chunk = search_result.chunk

        Source.new(
          chunk_id: chunk.id,
          document_id: extract_document_id(chunk),
          content: chunk.content,
          position: search_result.position,
          original_position: search_result.original_position,
          vector_position: search_result.vector_position,
          text_position: search_result.text_position,
          distance: search_result.distance,
          similarity: search_result.similarity,
          text_score: search_result.text_score,
          normalized_text_score: search_result.normalized_text_score,
          hybrid_score: search_result.hybrid_score,
          multi_query_score: search_result.multi_query_score,
          matched_queries: search_result.matched_queries,
          query_match_count: search_result.query_match_count,
          best_query_position: search_result.best_query_position,
          rerank_score: search_result.rerank_score,
          lexical_score: search_result.lexical_score,
          matched_terms: search_result.matched_terms,
          cross_encoder_score: search_result.cross_encoder_score,
          cross_encoder_reason: search_result.cross_encoder_reason,
          combined_score: search_result.combined_score,
          mmr_score: search_result.mmr_score,
          redundancy_score: search_result.redundancy_score,
          context_chunk_ids: context_chunk_ids_for(
            chunk,
            parent_retrieval
          ),
          cited: cited_chunk_ids&.include?(chunk.id)
        )
      end
    end

    def context_chunk_ids_for(source_chunk, parent_retrieval)
      return [ source_chunk.id ] unless parent_retrieval

      group =
        parent_retrieval.groups.find do |item|
          item.document_id == source_chunk.document_id &&
            item.source_chunk_ids.include?(source_chunk.id)
        end

      group ? group.chunks.map(&:id) : [ source_chunk.id ]
    end

    def extract_document_id(chunk)
      return chunk.document_id if chunk.respond_to?(:document_id)
      return chunk.document.id if chunk.respond_to?(:document)

      nil
    end

    def normalized_question
      @normalized_question ||= question.strip
    end

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
