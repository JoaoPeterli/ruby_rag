module Documents
  VectorSearchResult = Data.define(
    :chunk_id,
    :document_id,
    :content,
    :position,
    :distance,
    :score,
    :metadata
  )
end
