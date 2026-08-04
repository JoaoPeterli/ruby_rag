require "test_helper"

class Documents::AccountScopeBuilderTest < ActiveSupport::TestCase
  def build_chunk(account)
    document = Document.create!(
      title: "Manual de Teste",
      content: "Conteudo de teste do documento.",
      status: "completed",
      account: account
    )

    document.document_chunks.create!(content: "Trecho de teste.", position: 0)
  end

  test "returns only chunks belonging to the given account" do
    account_a = Account.create!(name: "Conta A")
    account_b = Account.create!(name: "Conta B")

    chunk_a = build_chunk(account_a)
    build_chunk(account_b)

    scoped = Documents::AccountScopeBuilder.call(account_id: account_a.id)

    assert_equal [ chunk_a.id ], scoped.pluck(:id)
  end

  test "returns the unrestricted scope when account_id is nil" do
    account = Account.create!(name: "Conta Unica")
    chunk = build_chunk(account)

    scoped = Documents::AccountScopeBuilder.call(account_id: nil)

    assert_includes scoped.pluck(:id), chunk.id
  end

  test "applies the account filter on top of a given base relation" do
    account_a = Account.create!(name: "Conta A")
    account_b = Account.create!(name: "Conta B")

    build_chunk(account_a)
    chunk_b = build_chunk(account_b)

    scoped = Documents::AccountScopeBuilder.call(
      scope: DocumentChunk.where(id: chunk_b.id),
      account_id: account_a.id
    )

    assert_empty scoped
  end
end
