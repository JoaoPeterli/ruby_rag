# frozen_string_literal: true

class RemoveQuestionEmbeddingFromRagSemanticCacheEntries < ActiveRecord::Migration[8.0]
  def change
    remove_index :rag_semantic_cache_entries, name: "index_rag_semantic_cache_on_embedding_hnsw"
    remove_column :rag_semantic_cache_entries, :question_embedding, :vector, limit: 1536, null: false
  end
end
