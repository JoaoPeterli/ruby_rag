require "test_helper"

class Documents::CitationEngine::ServiceTest < ActiveSupport::TestCase
  SOURCES = [
    { source_number: 1, chunk_id: 101, document_id: 1, position: 1 },
    { source_number: 2, chunk_id: 102, document_id: 1, position: 2 },
    { source_number: 3, chunk_id: 103, document_id: 1, position: 3 },
    { source_number: 4, chunk_id: 104, document_id: 1, position: 4 }
  ].freeze

  test "parses single citations" do
    result = Documents::CitationEngine::Service.call(
      answer: "O sistema faz X [FONTE 1] e Y [FONTE 2].",
      sources: SOURCES
    )

    assert_equal [ 1, 2 ], result.cited_source_numbers
    assert_equal [ 101, 102 ], result.cited_chunk_ids
  end

  test "parses comma-separated and range citations" do
    result = Documents::CitationEngine::Service.call(
      answer: "Ver [FONTE 1, FONTE 3] e também [FONTE 2 a 4].",
      sources: SOURCES
    )

    assert_equal [ 1, 2, 3, 4 ], result.cited_source_numbers
  end

  test "computes coverage and uncited sources" do
    result = Documents::CitationEngine::Service.call(
      answer: "Apenas [FONTE 1].",
      sources: SOURCES
    )

    assert_equal 0.25, result.citation_coverage
    assert_equal [ 2, 3, 4 ], result.uncited_source_numbers
  end

  test "ignores citation numbers that do not match any source" do
    result = Documents::CitationEngine::Service.call(
      answer: "Fonte inexistente [FONTE 99].",
      sources: SOURCES
    )

    assert_equal 0, result.citation_count
  end

  test "answer without citations yields zero coverage" do
    result = Documents::CitationEngine::Service.call(
      answer: "Não encontrei informações suficientes.",
      sources: SOURCES
    )

    assert_not result.any_citations?
    assert_equal 0.0, result.citation_coverage
  end

  test "raises for invalid sources" do
    assert_raises(Documents::CitationEngine::Service::InvalidSourcesError) do
      Documents::CitationEngine::Service.call(answer: "texto", sources: nil)
    end
  end
end
