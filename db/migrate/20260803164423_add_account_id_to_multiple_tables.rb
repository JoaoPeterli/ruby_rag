# frozen_string_literal: true

class AddAccountIdToMultipleTables < ActiveRecord::Migration[8.0]
  def up
    add_reference :documents, :account, foreign_key: true, index: true
    add_reference :document_chunks, :account, foreign_key: true, index: true
    add_reference :rag_queries, :account, foreign_key: true, index: true
    add_reference :rag_eval_cases, :account, foreign_key: true, index: true
    add_reference :rag_semantic_cache_entries, :account, foreign_key: true, index: true

    # rag_queries/rag_eval_cases/rag_semantic_cache_entries ficam NULL
    # pra dados históricos (são logs/config, não conteúdo de acesso
    # controlado) — só documents/document_chunks precisam de backfill,
    # porque a partir de agora toda busca é escopada por account_id e
    # um chunk sem dono ficaria invisível pra sempre.
    default_account_id = create_account!(
      name: "Conta Padrão (dados existentes)",
      operator: false
    )

    operator_account_id = create_account!(
      name: "Operador AverbGo",
      operator: true
    )

    execute(
      "UPDATE documents SET account_id = #{default_account_id} " \
      "WHERE account_id IS NULL"
    )

    execute(
      "UPDATE document_chunks SET account_id = #{default_account_id} " \
      "WHERE account_id IS NULL"
    )

    say "Conta padrão id=#{default_account_id} e conta operadora " \
        "id=#{operator_account_id} criadas. As api_keys foram " \
        "impressas acima (nas mensagens \"api_key gerada\") — copie " \
        "agora, elas não ficam guardadas em nenhum outro lugar."
  end

  def down
    remove_reference :documents, :account
    remove_reference :document_chunks, :account
    remove_reference :rag_queries, :account
    remove_reference :rag_eval_cases, :account
    remove_reference :rag_semantic_cache_entries, :account

    execute "DELETE FROM accounts"
  end

  private

  def create_account!(name:, operator:)
    api_key = SecureRandom.hex(32)

    result = execute(<<~SQL)
      INSERT INTO accounts (name, api_key, operator, active, created_at, updated_at)
      VALUES (#{quote(name)}, #{quote(api_key)}, #{operator}, true, now(), now())
      RETURNING id
    SQL

    say "api_key gerada para #{name.inspect}: #{api_key}"

    result.first["id"]
  end
end
