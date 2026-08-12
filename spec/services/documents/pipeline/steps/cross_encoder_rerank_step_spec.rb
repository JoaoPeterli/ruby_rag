require "rails_helper"

RSpec.describe Documents::Pipeline::Steps::CrossEncoderRerankStep do
  def build_context(reranked_results: [], merged_results: [], hybrid_results: {}, enabled:, metadata: {})
    context = Documents::Pipeline::Context.new(question: "Qual o prazo?")
    context.reranked_results = reranked_results
    context.merged_results = merged_results
    context.hybrid_results = hybrid_results
    context.metadata[:cross_encoder_enabled] = enabled
    metadata.each { |key, value| context.metadata[key] = value }
    context
  end

  def full_metadata
    {
      cross_encoder_candidate_limit: 20, cross_encoder_rerank_limit: 10,
      cross_encoder_minimum_score: 0.35, cross_encoder_weight: 0.75,
      cross_encoder_retrieval_weight: 0.25, cross_encoder_batch_size: 5
    }
  end

  def unreachable_service
    Class.new { define_singleton_method(:call) { |**_kwargs| raise "não deveria ser chamado" } }
  end

  it "passes results through unchanged when disabled" do
    context = build_context(reranked_results: [ :a, :b ], enabled: false)

    Documents::Pipeline::Steps::CrossEncoderRerankStep.call(context: context, cross_encoder_service: unreachable_service)

    expect(context.cross_encoder_results).to eq([ :a, :b ])
  end

  it "returns an empty list when enabled but there is nothing to rerank" do
    context = build_context(enabled: true)

    Documents::Pipeline::Steps::CrossEncoderRerankStep.call(context: context, cross_encoder_service: unreachable_service)

    expect(context.cross_encoder_results).to be_empty
  end

  it "prefers reranked_results, falling back to merged_results, then hybrid_results" do
    # enabled: false so available_results is exercised without requiring
    # the cross_encoder_service metadata (call short-circuits before that).
    context = build_context(reranked_results: [ :r ], merged_results: [ :m ], hybrid_results: { "q" => [ :h ] }, enabled: false)
    Documents::Pipeline::Steps::CrossEncoderRerankStep.call(context: context, cross_encoder_service: unreachable_service)
    expect(context.cross_encoder_results).to eq([ :r ])

    context2 = build_context(reranked_results: [], merged_results: [ :m ], hybrid_results: { "q" => [ :h ] }, enabled: false)
    Documents::Pipeline::Steps::CrossEncoderRerankStep.call(context: context2, cross_encoder_service: unreachable_service)
    expect(context2.cross_encoder_results).to eq([ :m ])

    context3 = build_context(reranked_results: [], merged_results: [], hybrid_results: { "q" => [ :h ] }, enabled: false)
    Documents::Pipeline::Steps::CrossEncoderRerankStep.call(context: context3, cross_encoder_service: unreachable_service)
    expect(context3.cross_encoder_results).to eq([ :h ])
  end

  it "reranks with the configured weights and records metrics" do
    cross_encoder_result = Documents::CrossEncoder::Result.new(
      results: [ :ranked_a, :ranked_b ], scores: { a: 0.9 }, original_count: 2,
      evaluated_count: 2, reranked_count: 2, average_score: 0.8,
      duration_ms: 5.0, model: "fake-model", strategy: "llm_batch"
    )

    received = nil
    service = Class.new { define_singleton_method(:call) { |**kwargs| received = kwargs; cross_encoder_result } }

    context = build_context(reranked_results: [ :a, :b ], enabled: true, metadata: full_metadata)

    Documents::Pipeline::Steps::CrossEncoderRerankStep.call(context: context, cross_encoder_service: service)

    expect(context.cross_encoder_results).to eq([ :ranked_a, :ranked_b ])
    expect(context.cross_encoder).to eq(cross_encoder_result)
    expect(received[:rerank_limit]).to eq(10)
    expect(received[:cross_encoder_weight]).to be_within(0.0001).of(0.75)
    expect(received[:strategy_options][:batch_size]).to eq(5)
    expect(context.metrics[:cross_encoder_output_count]).to eq(2)
    expect(context.metrics[:cross_encoder_average_score]).to be_within(0.0001).of(0.8)
    expect(context.metrics[:cross_encoder_model]).to eq("fake-model")
  end

  it "falls back to the available results and records a stage failure when the service raises" do
    raising_service = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise Documents::CrossEncoder::Service::RerankError, "falha" }
    end

    context = build_context(reranked_results: [ :a, :b ], enabled: true, metadata: full_metadata)

    Documents::Pipeline::Steps::CrossEncoderRerankStep.call(context: context, cross_encoder_service: raising_service)

    expect(context.cross_encoder_results).to eq([ :a, :b ])
    expect(context.metadata[:stage_failures].size).to eq(1)
    expect(context.metadata[:stage_failures].first[:stage]).to eq("cross_encoder")
  end
end
