# frozen_string_literal: true

module Documents
  module CitationEngine
    Result = Data.define(
      :answer,
      :citations,
      :cited_source_numbers,
      :uncited_source_numbers,
      :citation_count,
      :source_count,
      :citation_coverage,
      :duration_ms
    ) do
      def cited_chunk_ids
        citations.map(&:chunk_id).uniq
      end

      def any_citations?
        citation_count.positive?
      end
    end
  end
end
