# frozen_string_literal: true

module Documents
  module CitationEngine
    Citation = Data.define(
      :source_number,
      :chunk_id,
      :document_id,
      :position
    )
  end
end
