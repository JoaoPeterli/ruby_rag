# frozen_string_literal: true

class AddMetadataFieldsToDocuments < ActiveRecord::Migration[8.0]
  def change
    add_column :documents, :ramo, :string
    add_column :documents, :seguradora, :string
    add_column :documents, :cliente, :string
    add_column :documents, :tipo_documento, :string
    add_column :documents, :vigencia_ano, :integer

    add_index :documents, :ramo
    add_index :documents, :seguradora
    add_index :documents, :cliente
    add_index :documents, :tipo_documento
    add_index :documents, :vigencia_ano

    add_index :documents,
              :metadata,
              using: :gin
  end
end
