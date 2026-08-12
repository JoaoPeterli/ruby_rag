require "rails_helper"

RSpec.describe Documents::GroundednessCheckService do
  it "treats an explicit refusal as grounded and refused" do
    result = Documents::GroundednessCheckService.call(
      answer: "Não encontrei informações suficientes nas fontes fornecidas.",
      citation_count: 0
    )

    expect(result.grounded).to be_truthy
    expect(result.refused).to be_truthy
    expect(result.reason).to be_nil
  end

  it "treats a cited answer as grounded and not refused" do
    result = Documents::GroundednessCheckService.call(
      answer: "O sistema busca apolice [FONTE 1].",
      citation_count: 1
    )

    expect(result.grounded).to be_truthy
    expect(result.refused).to be_falsey
  end

  it "flags a confident answer without citations as ungrounded" do
    result = Documents::GroundednessCheckService.call(
      answer: "O sistema com certeza faz isso.",
      citation_count: 0
    )

    expect(result.grounded).to be_falsey
    expect(result.refused).to be_falsey
    expect(result.reason).to be_present
  end

  it "raises for a non-string answer" do
    expect do
      Documents::GroundednessCheckService.call(answer: nil, citation_count: 0)
    end.to raise_error(Documents::GroundednessCheckService::InvalidAnswerError)
  end
end
