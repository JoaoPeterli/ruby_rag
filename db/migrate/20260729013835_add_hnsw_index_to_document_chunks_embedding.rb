class AddHnswIndexToDocumentChunksEmbedding <
  ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE INDEX index_document_chunks_on_embedding_hnsw
      ON document_chunks
      USING hnsw (embedding vector_cosine_ops)
    SQL
  end

  def down
    execute <<~SQL
      DROP INDEX IF EXISTS
      index_document_chunks_on_embedding_hnsw
    SQL
  end
end
