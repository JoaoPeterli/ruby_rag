require "rails_helper"

RSpec.describe Documents::PipelineObservability::Report do
  it "is a plain data holder exposing every field it was built with" do
    report = Documents::PipelineObservability::Report.new(
      stage_metrics: { hybrid_search: 12.3 },
      stage_failures: [],
      candidate_counts: { results: 5 },
      token_usage: { prompt_tokens: 10 },
      cost: nil,
      retrieval_duration_ms: 42.0,
      total_duration_ms: 55.0
    )

    expect(report.stage_metrics).to eq({ hybrid_search: 12.3 })
    expect(report.stage_failures).to eq([])
    expect(report.candidate_counts).to eq({ results: 5 })
    expect(report.token_usage).to eq({ prompt_tokens: 10 })
    expect(report.cost).to be_nil
    expect(report.retrieval_duration_ms).to eq(42.0)
    expect(report.total_duration_ms).to eq(55.0)
  end
end
