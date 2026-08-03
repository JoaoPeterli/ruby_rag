# frozen_string_literal: true

class CreateRagEvalCases < ActiveRecord::Migration[8.0]
  def change
    create_table :rag_eval_cases do |t|
      t.text :question, null: false
      t.text :expected_answer
      t.jsonb :expected_chunk_ids, default: [], null: false
      t.jsonb :expected_document_ids, default: [], null: false
      t.string :category
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :rag_eval_cases, :category
    add_index :rag_eval_cases, :active
  end
end
