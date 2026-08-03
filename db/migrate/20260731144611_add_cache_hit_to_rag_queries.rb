# frozen_string_literal: true

class AddCacheHitToRagQueries < ActiveRecord::Migration[8.0]
  def change
    add_column :rag_queries, :cache_hit, :boolean, default: false, null: false
  end
end
