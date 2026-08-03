# frozen_string_literal: true

class CreateRagEvalRunsAndResults < ActiveRecord::Migration[8.0]
  def change
    create_table :rag_eval_runs do |t|
      t.integer :cases_count, null: false, default: 0
      t.jsonb :summary, default: {}, null: false
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    create_table :rag_eval_results do |t|
      t.references :rag_eval_run, null: false, foreign_key: true
      t.references :rag_eval_case, null: false, foreign_key: true
      t.text :answer
      t.jsonb :metrics, default: {}, null: false
      t.integer :duration_ms
      t.boolean :errored, default: false, null: false
      t.text :error_message

      t.timestamps
    end
  end
end
