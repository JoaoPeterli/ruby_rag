require "test_helper"

class Documents::GroundednessCheckServiceTest < ActiveSupport::TestCase
  test "explicit refusal is grounded and refused" do
    result = Documents::GroundednessCheckService.call(
      answer: "Não encontrei informações suficientes nas fontes fornecidas.",
      citation_count: 0
    )

    assert result.grounded
    assert result.refused
    assert_nil result.reason
  end

  test "cited answer is grounded and not refused" do
    result = Documents::GroundednessCheckService.call(
      answer: "O sistema busca apolice [FONTE 1].",
      citation_count: 1
    )

    assert result.grounded
    assert_not result.refused
  end

  test "confident answer without citations is flagged as ungrounded" do
    result = Documents::GroundednessCheckService.call(
      answer: "O sistema com certeza faz isso.",
      citation_count: 0
    )

    assert_not result.grounded
    assert_not result.refused
    assert result.reason.present?
  end

  test "raises for non-string answer" do
    assert_raises(Documents::GroundednessCheckService::InvalidAnswerError) do
      Documents::GroundednessCheckService.call(answer: nil, citation_count: 0)
    end
  end
end
