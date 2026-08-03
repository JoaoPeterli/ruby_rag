require "test_helper"

class DocumentChunkTest < ActiveSupport::TestCase
  def build_document
    Document.create!(
      title: "Manual de Teste",
      content: "Conteudo de teste do documento.",
      status: "completed",
      account: sample_account
    )
  end

  def sample_account
    @sample_account ||= Account.create!(name: "Conta de Teste")
  end

  def build_chunk(document, **overrides)
    document.document_chunks.new(
      {
        content: "Trecho de teste.",
        position: 0
      }.merge(overrides)
    )
  end

  test "requires content and a non-negative integer position" do
    document = build_document

    chunk = build_chunk(document, content: nil, position: nil)
    assert_not chunk.valid?
    assert_includes chunk.errors.attribute_names, :content
    assert_includes chunk.errors.attribute_names, :position

    negative = build_chunk(document, position: -1)
    assert_not negative.valid?
    assert_includes negative.errors.attribute_names, :position
  end

  test "position must be unique within the same document" do
    document = build_document
    build_chunk(document, position: 0).save!

    duplicate = build_chunk(document, content: "Outro trecho.", position: 0)

    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :position
  end

  test "the same position is allowed across different documents" do
    first_document = build_document
    second_document = build_document

    build_chunk(first_document, position: 0).save!
    other = build_chunk(second_document, position: 0)

    assert other.valid?
  end

  test "generates a content_hash automatically" do
    chunk = build_chunk(build_document)
    chunk.save!

    assert chunk.content_hash.present?
  end

  test "duplicate content within the same document is rejected" do
    document = build_document
    build_chunk(document, content: "Conteudo repetido", position: 0).save!

    duplicate = build_chunk(document, content: "Conteudo repetido", position: 1)

    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :content_hash
  end

  test "ordered scope sorts chunks by position" do
    document = build_document
    build_chunk(document, content: "Terceiro", position: 2).save!
    build_chunk(document, content: "Primeiro", position: 0).save!
    build_chunk(document, content: "Segundo", position: 1).save!

    assert_equal [ 0, 1, 2 ], document.document_chunks.ordered.pluck(:position)
  end
end
