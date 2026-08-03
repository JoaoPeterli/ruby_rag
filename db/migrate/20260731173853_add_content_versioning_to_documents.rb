# frozen_string_literal: true

class AddContentVersioningToDocuments < ActiveRecord::Migration[8.0]
  def change
    add_column :documents, :content_hash, :string
    add_column :documents, :content_version, :integer, default: 1, null: false

    add_index :documents, :content_hash
  end
end
