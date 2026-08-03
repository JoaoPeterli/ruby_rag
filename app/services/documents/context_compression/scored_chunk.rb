# frozen_string_literal: true

module Documents
  module ContextCompression
    ScoredChunk = Data.define(
      :chunk,
      :similarity,
      :source
    )
  end
end
