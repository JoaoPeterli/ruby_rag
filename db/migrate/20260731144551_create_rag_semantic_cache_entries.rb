# frozen_string_literal: true

class CreateRagSemanticCacheEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :rag_semantic_cache_entries do |t|
      t.text :question, null: false
      t.vector :question_embedding, limit: 1536, null: false
      t.text :answer, null: false
      t.jsonb :sources, default: [], null: false
      t.string :model
      t.float :confidence_score
      t.string :confidence_level
      t.integer :hits, default: 0, null: false
      t.datetime :last_hit_at
      t.datetime :expires_at

      t.timestamps
    end

    add_index :rag_semantic_cache_entries,
              :question_embedding,
              using: :hnsw,
              opclass: :vector_cosine_ops,
              name: "index_rag_semantic_cache_on_embedding_hnsw"

    add_index :rag_semantic_cache_entries, :expires_at
  end
end
