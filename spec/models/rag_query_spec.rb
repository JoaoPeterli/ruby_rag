require "rails_helper"

RSpec.describe RagQuery do
  it "requires a question and a valid status" do
    query = RagQuery.new(question: nil, status: "unknown")

    expect(query).not_to be_valid
    expect(query.errors.attribute_names).to include(:question, :status)
  end

  it "accepts every declared status" do
    RagQuery::STATUSES.each do |status|
      query = RagQuery.new(question: "Pergunta de teste", status: status)

      expect(query).to be_valid, "esperava #{status} ser válido"
    end
  end

  it "has_one rag_answer and has_many rag_retrieval_results" do
    query = create(:rag_query)
    answer = create(:rag_answer, rag_query: query)

    expect(query.reload.rag_answer).to eq(answer)
    expect(query.rag_retrieval_results).to eq([])
  end
end
