# frozen_string_literal: true

class RemoveEmbeddingFromDocumentChunks < ActiveRecord::Migration[8.0]
  def change
    remove_index :document_chunks, name: "index_document_chunks_on_embedding_hnsw"
    remove_column :document_chunks, :embedding, :vector, limit: 1536
  end
end
