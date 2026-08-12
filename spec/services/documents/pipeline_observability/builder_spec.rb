require "rails_helper"

RSpec.describe Documents::PipelineObservability::Builder do
  def retrieval_result_double_class
    @retrieval_result_double_class ||= Struct.new(
      :metrics, :stage_failures, :duration_ms,
      :results, :context_chunks, :compressed_chunks, :cross_encoder_results,
      keyword_init: true
    )
  end

  def qa_result_double_class
    @qa_result_double_class ||= Struct.new(
      :duration_ms, :prompt_tokens, :completion_tokens, :total_tokens, :model,
      keyword_init: true
    )
  end

  def retrieval_result
    retrieval_result_double_class.new(
      metrics: { hybrid_search: 12.3 },
      stage_failures: [],
      duration_ms: 42.0,
      results: [ 1, 2, 3 ],
      context_chunks: [ 1, 2 ],
      compressed_chunks: [ 1 ],
      cross_encoder_results: [ 1, 2, 3 ]
    )
  end

  it "builds a report from retrieval metrics alone when there is no qa_result" do
    report = Documents::PipelineObservability::Builder.call(retrieval_result: retrieval_result)

    expect(report.stage_metrics).to eq({ hybrid_search: 12.3 })
    expect(report.candidate_counts).to eq({ results: 3, context_chunks: 2, compressed_chunks: 1, cross_encoder_results: 3 })
    expect(report.token_usage).to be_nil
    expect(report.cost).to be_nil
    expect(report.retrieval_duration_ms).to eq(42.0)
    expect(report.total_duration_ms).to eq(42.0)
  end

  it "includes token usage, cost and the qa_result's own total duration when a qa_result is given" do
    qa_result = qa_result_double_class.new(
      duration_ms: 80.0, prompt_tokens: 100, completion_tokens: 40, total_tokens: 140, model: "gpt-test"
    )

    received = nil
    fake_cost_calculator = Class.new do
      define_singleton_method(:call) do |**kwargs|
        received = kwargs
        Ai::CostCalculator::Result.new(
          model: "gpt-test", prompt_tokens: 100, completion_tokens: 40, total_tokens: 140,
          prompt_cost_usd: 0.001, completion_cost_usd: 0.002, total_cost_usd: 0.003, priced: true
        )
      end
    end

    report = Documents::PipelineObservability::Builder.call(
      retrieval_result: retrieval_result,
      qa_result: qa_result,
      cost_calculator: fake_cost_calculator
    )

    expect(report.token_usage).to eq({ prompt_tokens: 100, completion_tokens: 40, total_tokens: 140 })
    expect(report.cost.total_cost_usd).to eq(0.003)
    expect(report.total_duration_ms).to eq(80.0)
    expect(received).to eq({ model: "gpt-test", prompt_tokens: 100, completion_tokens: 40 })
  end
end
