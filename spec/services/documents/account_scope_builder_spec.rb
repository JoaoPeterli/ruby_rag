require "rails_helper"

RSpec.describe Documents::AccountScopeBuilder do
  def build_chunk(account)
    document = create(:document, account: account)

    document.document_chunks.create!(content: "Trecho de teste.", position: 0)
  end

  it "returns only chunks belonging to the given account" do
    account_a = create(:account)
    account_b = create(:account)

    chunk_a = build_chunk(account_a)
    build_chunk(account_b)

    scoped = Documents::AccountScopeBuilder.call(account_id: account_a.id)

    expect(scoped.pluck(:id)).to eq([ chunk_a.id ])
  end

  it "returns the unrestricted scope when account_id is nil" do
    account = create(:account)
    chunk = build_chunk(account)

    scoped = Documents::AccountScopeBuilder.call(account_id: nil)

    expect(scoped.pluck(:id)).to include(chunk.id)
  end

  it "applies the account filter on top of a given base relation" do
    account_a = create(:account)
    account_b = create(:account)

    build_chunk(account_a)
    chunk_b = build_chunk(account_b)

    scoped = Documents::AccountScopeBuilder.call(
      scope: DocumentChunk.where(id: chunk_b.id),
      account_id: account_a.id
    )

    expect(scoped).to be_empty
  end
end
