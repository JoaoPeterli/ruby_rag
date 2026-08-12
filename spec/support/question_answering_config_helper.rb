# frozen_string_literal: true

# Compartilhado pelos specs dos steps de Documents::Pipeline::Steps::Answering
# (ver test/services/documents/pipeline/steps/answering/*_test.rb original —
# cada um definia essa mesma fábrica de Config localmente).
module QuestionAnsweringConfigHelper
  def base_config(**overrides)
    Documents::QuestionAnsweringService::Config.new(
      search_limit: 5, candidate_limit: 20, minimum_similarity: 0.30, mmr_lambda: 0.70,
      query_expansion_enabled: nil, multi_query_enabled: nil, metadata_extraction_enabled: nil,
      cross_encoder_enabled: nil, parent_retrieval_enabled: nil, context_compression_enabled: nil,
      citation_engine_enabled: true, groundedness_check_enabled: true, hallucination_check_enabled: false,
      confidence_score_enabled: true, persist_enabled: false,
      semantic_cache_enabled: false, semantic_cache_minimum_similarity: 0.95, semantic_cache_ttl: 3600,
      token_budget_enabled: false, token_budget_total: 8000, token_budget_response_reserve: 800,
      token_budget_system_prompt_reserve: 300,
      adaptive_retrieval_enabled: false, query_router_enabled: false, query_rewrite_enabled: false,
      retrieval_pipeline: nil, context_builder: nil, prompt_builder: nil,
      chat_completion_service: nil, chat_stream_service: nil, citation_engine: nil,
      groundedness_check_service: nil, hallucination_check_service: nil, confidence_score_service: nil,
      persistence_service: nil, embedding_service: nil, semantic_cache_lookup_service: nil,
      semantic_cache_store_service: nil, token_budget_service: nil, adaptive_retrieval_planner: nil,
      query_router_service: nil, query_rewrite_service: nil
    ).with(**overrides)
  end
end

RSpec.configure do |config|
  config.include QuestionAnsweringConfigHelper
end
