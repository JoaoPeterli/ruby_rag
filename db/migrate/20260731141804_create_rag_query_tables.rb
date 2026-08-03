# frozen_string_literal: true

class CreateRagQueryTables < ActiveRecord::Migration[8.0]
  def change
    create_table :rag_queries do |t|
      t.text :question, null: false
      t.text :normalized_question
      t.text :search_query
      t.string :status, null: false, default: "completed"
      t.integer :duration_ms
      t.integer :total_tokens
      t.jsonb :metrics, default: {}, null: false

      t.timestamps
    end

    add_index :rag_queries, :status
    add_index :rag_queries, :created_at

    create_table :rag_retrieval_results do |t|
      t.references :rag_query, null: false, foreign_key: true
      t.references :document_chunk,
                    null: true,
                    foreign_key: { on_delete: :nullify }
      t.integer :position
      t.boolean :cited, default: false, null: false
      t.float :hybrid_score
      t.float :rerank_score
      t.float :cross_encoder_score
      t.float :combined_score
      t.float :mmr_score

      t.timestamps
    end

    create_table :rag_answers do |t|
      t.references :rag_query, null: false, foreign_key: true
      t.text :answer, null: false
      t.string :model
      t.boolean :grounded
      t.boolean :refused
      t.float :citation_coverage
      t.float :hallucination_rate
      t.float :confidence_score
      t.string :confidence_level
      t.integer :prompt_tokens
      t.integer :completion_tokens
      t.integer :total_tokens

      t.timestamps
    end

    add_index :rag_answers, :confidence_level

    create_table :rag_feedbacks do |t|
      t.references :rag_answer, null: false, foreign_key: true
      t.string :rating, null: false
      t.text :reason

      t.timestamps
    end

    add_index :rag_feedbacks, :rating
  end
end
