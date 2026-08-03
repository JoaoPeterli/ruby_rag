require "test_helper"

class DocumentTest < ActiveSupport::TestCase
  def build_document(**overrides)
    Document.new(
      {
        title: "Manual de Teste",
        content: "Conteudo de teste do documento.",
        status: "pending",
        account: sample_account
      }.merge(overrides)
    )
  end

  def sample_account
    @sample_account ||= Account.create!(name: "Conta de Teste")
  end

  test "requires title and content" do
    document = build_document(title: nil, content: nil)

    assert_not document.valid?
    assert_includes document.errors.attribute_names, :title
    assert_includes document.errors.attribute_names, :content
  end

  test "defaults status to pending on create" do
    document = build_document(status: nil)
    document.save!

    assert_equal "pending", document.status
  end

  test "rejects an unknown status" do
    document = build_document(status: "unknown")

    assert_not document.valid?
    assert_includes document.errors.attribute_names, :status
  end

  test "vigencia_ano must be a plausible year when present" do
    document = build_document(vigencia_ano: 1899)

    assert_not document.valid?
    assert_includes document.errors.attribute_names, :vigencia_ano
  end

  test "vigencia_ano is optional" do
    document = build_document(vigencia_ano: nil)

    assert document.valid?
  end

  test "generates a content_hash from the normalized content" do
    document = build_document
    document.save!

    assert document.content_hash.present?
  end

  test "the same normalized content produces the same hash" do
    first = build_document(content: "Ola   mundo").tap(&:save!)
    second = build_document(content: "Ola mundo").tap(&:save!)

    assert_equal first.content_hash, second.content_hash
  end

  test "changing the content changes the hash" do
    document = build_document
    document.save!
    original_hash = document.content_hash

    document.update!(content: "Conteudo totalmente diferente.")

    assert_not_equal original_hash, document.content_hash
  end

  test "already_ingested_and_unchanged? is false before any ingestion metadata exists" do
    document = build_document(status: "completed")
    document.save!

    assert_not document.already_ingested_and_unchanged?
  end

  test "already_ingested_and_unchanged? is true once the hash matches the last ingested hash" do
    document = build_document(status: "completed")
    document.save!
    document.update_columns(
      metadata: { "ingested_content_hash" => document.content_hash }
    )

    assert document.already_ingested_and_unchanged?
  end

  test "already_ingested_and_unchanged? is false when the content changed after ingestion" do
    document = build_document(status: "completed")
    document.save!
    document.update_columns(
      metadata: { "ingested_content_hash" => document.content_hash }
    )

    document.update!(content: "Conteudo alterado depois da ingestao.")

    assert_not document.already_ingested_and_unchanged?
  end

  test "already_ingested_and_unchanged? is false when the document is not completed" do
    document = build_document(status: "queued")
    document.save!
    document.update_columns(
      metadata: { "ingested_content_hash" => document.content_hash }
    )

    assert_not document.already_ingested_and_unchanged?
  end
end
