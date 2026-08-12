require "rails_helper"

RSpec.describe Documents::Pipeline::Steps::RerankStep do
  it "passes the question, merged_results and candidate_limit through to the reranking service" do
    context = Documents::Pipeline::Context.new(question: "Qual o prazo?")
    context.merged_results = [ :result_a, :result_b ]
    context.metadata[:candidate_limit] = 15

    received = nil
    fake_service = Class.new do
      define_singleton_method(:call) do |**kwargs|
        received = kwargs
        [ :reranked_a, :reranked_b ]
      end
    end

    Documents::Pipeline::Steps::RerankStep.call(context: context, reranking_service: fake_service)

    expect(received[:question]).to eq("Qual o prazo?")
    expect(received[:search_results]).to eq([ :result_a, :result_b ])
    expect(received[:limit]).to eq(15)
    expect(context.reranked_results).to eq([ :reranked_a, :reranked_b ])
    expect(context.metrics[:rerank]).to be_a(Numeric)
  end
end
