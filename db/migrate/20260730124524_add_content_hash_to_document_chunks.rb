# frozen_string_literal: true

require "digest"

class AddContentHashToDocumentChunks < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_column :document_chunks, :content_hash, :string

    backfill_content_hashes
    remove_duplicate_chunks

    change_column_null :document_chunks, :content_hash, false

    add_index(
      :document_chunks,
      %i[document_id content_hash],
      unique: true,
      algorithm: :concurrently,
      name: "index_document_chunks_on_document_and_content_hash"
    )
  end

  def down
    remove_index(
      :document_chunks,
      name: "index_document_chunks_on_document_and_content_hash",
      algorithm: :concurrently
    )

    remove_column :document_chunks, :content_hash
  end

  private

  def backfill_content_hashes
    say_with_time "Gerando hashes dos chunks existentes" do
      document_chunk_model.find_each do |chunk|
        chunk.update_columns(
          content_hash: generate_hash(chunk.content)
        )
      end
    end
  end

  def remove_duplicate_chunks
    say_with_time "Removendo chunks duplicados" do
      duplicates = document_chunk_model
        .group(:document_id, :content_hash)
        .having("COUNT(*) > 1")
        .pluck(:document_id, :content_hash)

      duplicates.each do |document_id, content_hash|
        chunks = document_chunk_model
          .where(
            document_id: document_id,
            content_hash: content_hash
          )
          .order(:id)

        chunks.offset(1).delete_all
      end
    end
  end

  def generate_hash(content)
    Digest::SHA256.hexdigest(normalize_content(content))
  end

  def normalize_content(content)
    content.to_s
      .unicode_normalize(:nfkc)
      .gsub(/\r\n?/, "\n")
      .gsub(/[[:space:]]+/, " ")
      .strip
  end

  def document_chunk_model
    @document_chunk_model ||= Class.new(ActiveRecord::Base) do
      self.table_name = "document_chunks"
    end
  end
end
