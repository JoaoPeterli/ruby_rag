# frozen_string_literal: true

class AddSearchVectorToDocumentChunks < ActiveRecord::Migration[8.0]
  def up
    add_column(
      :document_chunks,
      :search_vector,
      :tsvector
    )

    execute <<~SQL
      UPDATE document_chunks
      SET search_vector =
        to_tsvector(
          'portuguese',
          COALESCE(content, '')
        );
    SQL

    change_column_null(
      :document_chunks,
      :search_vector,
      false
    )

    add_index(
      :document_chunks,
      :search_vector,
      using: :gin,
      name: "index_document_chunks_on_search_vector"
    )

    execute <<~SQL
      CREATE FUNCTION document_chunks_search_vector_update()
      RETURNS trigger AS $$
      BEGIN
        NEW.search_vector :=
          to_tsvector(
            'portuguese',
            COALESCE(NEW.content, '')
          );

        RETURN NEW;
      END
      $$ LANGUAGE plpgsql;
    SQL

    execute <<~SQL
      CREATE TRIGGER document_chunks_search_vector_trigger
      BEFORE INSERT OR UPDATE OF content
      ON document_chunks
      FOR EACH ROW
      EXECUTE FUNCTION document_chunks_search_vector_update();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS
        document_chunks_search_vector_trigger
      ON document_chunks;
    SQL

    execute <<~SQL
      DROP FUNCTION IF EXISTS
        document_chunks_search_vector_update();
    SQL

    remove_index(
      :document_chunks,
      name: "index_document_chunks_on_search_vector"
    )

    remove_column(
      :document_chunks,
      :search_vector
    )
  end
end
