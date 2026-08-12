require "rails_helper"

RSpec.describe Documents::Evaluation::Metrics do
  it "exposes the given metric values" do
    metrics = Documents::Evaluation::Metrics.new(
      retrieval_precision: 0.8,
      retrieval_recall: 0.6,
      chunk_relevance: 0.7,
      answer_faithfulness: 0.9,
      citation_coverage: 1.0,
      no_evidence_correct: true
    )

    expect(metrics.retrieval_precision).to eq(0.8)
    expect(metrics.retrieval_recall).to eq(0.6)
    expect(metrics.chunk_relevance).to eq(0.7)
    expect(metrics.answer_faithfulness).to eq(0.9)
    expect(metrics.citation_coverage).to eq(1.0)
    expect(metrics.no_evidence_correct).to be_truthy
  end
end
