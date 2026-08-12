require "rails_helper"

RSpec.describe Documents::Pipeline::Steps::MmrStep do
  def fake_mmr(&on_call)
    Class.new do
      define_singleton_method(:call) { |**kwargs| on_call.call(kwargs) }
    end
  end

  def base_context
    context = Documents::Pipeline::Context.new(question: "pergunta")
    context.metadata[:search_limit] = 5
    context.metadata[:mmr_lambda] = 0.7
    context
  end

  it "prefers cross_encoder_results over reranked_results and merged_results when present" do
    context = base_context
    context.cross_encoder_results = [ :from_cross_encoder ]
    context.reranked_results = [ :from_rerank ]
    context.merged_results = [ :from_merge ]

    received = nil
    Documents::Pipeline::Steps::MmrStep.call(
      context: context,
      mmr_service: fake_mmr { |kwargs| received = kwargs; [] }
    )

    expect(received[:results]).to eq([ :from_cross_encoder ])
  end

  it "falls back to reranked_results when there are no cross_encoder_results" do
    context = base_context
    context.cross_encoder_results = []
    context.reranked_results = [ :from_rerank ]
    context.merged_results = [ :from_merge ]

    received = nil
    Documents::Pipeline::Steps::MmrStep.call(
      context: context,
      mmr_service: fake_mmr { |kwargs| received = kwargs; [] }
    )

    expect(received[:results]).to eq([ :from_rerank ])
  end

  it "falls back to merged_results when neither cross_encoder_results nor reranked_results are present" do
    context = base_context
    context.cross_encoder_results = []
    context.reranked_results = []
    context.merged_results = [ :from_merge ]

    received = nil
    Documents::Pipeline::Steps::MmrStep.call(
      context: context,
      mmr_service: fake_mmr { |kwargs| received = kwargs; [] }
    )

    expect(received[:results]).to eq([ :from_merge ])
  end

  it "passes the configured search_limit and mmr_lambda through and stores the result" do
    context = base_context
    context.merged_results = [ :from_merge ]

    received = nil
    Documents::Pipeline::Steps::MmrStep.call(
      context: context,
      mmr_service: fake_mmr { |kwargs| received = kwargs; [ :mmr_result ] }
    )

    expect(received[:limit]).to eq(5)
    expect(received[:lambda_value]).to eq(0.7)
    expect(context.results).to eq([ :mmr_result ])
    expect(context.metrics[:mmr]).to be_a(Numeric)
  end
end
