require "rails_helper"

RSpec.describe RagEvalCase do
  it "requires a question" do
    eval_case = RagEvalCase.new(question: nil)

    expect(eval_case).not_to be_valid
    expect(eval_case.errors.attribute_names).to include(:question)
  end

  describe "#expects_answer?" do
    it "reflects whether expected_answer is present" do
      with_answer = RagEvalCase.new(question: "P", expected_answer: "Resposta esperada")
      without_answer = RagEvalCase.new(question: "P", expected_answer: nil)

      expect(with_answer.expects_answer?).to be(true)
      expect(without_answer.expects_answer?).to be(false)
    end
  end

  describe ".active" do
    it "only returns active cases" do
      active_case = create(:rag_eval_case, active: true)
      inactive_case = create(:rag_eval_case, active: false)

      result = RagEvalCase.active

      expect(result).to include(active_case)
      expect(result).not_to include(inactive_case)
    end
  end

  describe ".by_category" do
    it "filters by category" do
      factual = create(:rag_eval_case, category: "factual")
      create(:rag_eval_case, category: "resumo")

      expect(RagEvalCase.by_category("factual").to_a).to eq([ factual ])
    end
  end
end
