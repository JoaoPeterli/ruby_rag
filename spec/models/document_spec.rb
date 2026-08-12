require "rails_helper"

RSpec.describe Document do
  def build_document(**overrides)
    build(:document, status: "pending", **overrides)
  end

  it "requires title and content" do
    document = build_document(title: nil, content: nil)

    expect(document).not_to be_valid
    expect(document.errors.attribute_names).to include(:title, :content)
  end

  it "defaults status to pending on create" do
    document = build_document(status: nil)
    document.save!

    expect(document.status).to eq("pending")
  end

  it "rejects an unknown status" do
    document = build_document(status: "unknown")

    expect(document).not_to be_valid
    expect(document.errors.attribute_names).to include(:status)
  end

  it "allows a blank content when status is uploaded (aguardando OCR)" do
    document = build_document(status: "uploaded", content: nil)

    expect(document).to be_valid
  end

  it "requires content once the status leaves uploaded" do
    document = build_document(status: "pending", content: nil)

    expect(document).not_to be_valid
    expect(document.errors.attribute_names).to include(:content)
  end

  it "requires vigencia_ano to be a plausible year when present" do
    document = build_document(vigencia_ano: 1899)

    expect(document).not_to be_valid
    expect(document.errors.attribute_names).to include(:vigencia_ano)
  end

  it "allows a blank vigencia_ano" do
    document = build_document(vigencia_ano: nil)

    expect(document).to be_valid
  end

  it "generates a content_hash from the normalized content" do
    document = build_document
    document.save!

    expect(document.content_hash).to be_present
  end

  it "produces the same hash for the same normalized content" do
    first = build_document(content: "Ola   mundo").tap(&:save!)
    second = build_document(content: "Ola mundo").tap(&:save!)

    expect(second.content_hash).to eq(first.content_hash)
  end

  it "changes the hash when the content changes" do
    document = build_document
    document.save!
    original_hash = document.content_hash

    document.update!(content: "Conteudo totalmente diferente.")

    expect(document.content_hash).not_to eq(original_hash)
  end

  describe "#already_ingested_and_unchanged?" do
    it "is false before any ingestion metadata exists" do
      document = build_document(status: "completed")
      document.save!

      expect(document.already_ingested_and_unchanged?).to be(false)
    end

    it "is true once the hash matches the last ingested hash" do
      document = build_document(status: "completed")
      document.save!
      document.update_columns(metadata: { "ingested_content_hash" => document.content_hash })

      expect(document.already_ingested_and_unchanged?).to be(true)
    end

    it "is false when the content changed after ingestion" do
      document = build_document(status: "completed")
      document.save!
      document.update_columns(metadata: { "ingested_content_hash" => document.content_hash })

      document.update!(content: "Conteudo alterado depois da ingestao.")

      expect(document.already_ingested_and_unchanged?).to be(false)
    end

    it "is false when the document is not completed" do
      document = build_document(status: "queued")
      document.save!
      document.update_columns(metadata: { "ingested_content_hash" => document.content_hash })

      expect(document.already_ingested_and_unchanged?).to be(false)
    end
  end
end
