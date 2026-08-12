require "rails_helper"

RSpec.describe Documents::AdaptiveRetrievalPlanner do
  it "gives the simple plan for a short question, skipping expensive stages" do
    plan = Documents::AdaptiveRetrievalPlanner.call(question: "O que é apolice?")

    expect(plan.complexity).to eq(:simple)
    expect(plan.query_expansion_enabled).to be_falsey
    expect(plan.multi_query_enabled).to be_falsey
    expect(plan.cross_encoder_enabled).to be_falsey
  end

  it "triggers the complex plan for comparison keywords" do
    plan = Documents::AdaptiveRetrievalPlanner.call(
      question: "Compare o processo de busca de apolice com o de averbacao"
    )

    expect(plan.complexity).to eq(:complex)
    expect(plan.multi_query_enabled).to be_truthy
    expect(plan.cross_encoder_enabled).to be_truthy
  end

  it "lets an explicit category from the query router override the heuristic" do
    plan = Documents::AdaptiveRetrievalPlanner.call(
      question: "O que é apolice?",
      category: "comparacao"
    )

    expect(plan.complexity).to eq(:complex)
  end

  it "falls back to the standard plan for an unknown category" do
    plan = Documents::AdaptiveRetrievalPlanner.call(
      question: "Pergunta de tamanho médio sobre o processo de averbação",
      category: "algo_desconhecido"
    )

    expect(plan.complexity).to eq(:standard)
  end

  it "raises for a blank question" do
    expect do
      Documents::AdaptiveRetrievalPlanner.call(question: "   ")
    end.to raise_error(Documents::AdaptiveRetrievalPlanner::InvalidQuestionError)
  end
end
