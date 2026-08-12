require "rails_helper"

RSpec.describe Documents::MetadataFilters do
  it "empty returns a filter with every field blank" do
    filters = Documents::MetadataFilters.empty

    expect(filters.empty?).to be_truthy
    expect(filters.metadata).to eq({})
  end

  it "empty? is false when any field is present" do
    filters = Documents::MetadataFilters.empty.with(ramo: "RCF")

    expect(filters.empty?).to be_falsey
  end

  it "to_h drops blank fields" do
    filters = Documents::MetadataFilters.new(
      ramo: "RCF",
      seguradora: nil,
      cliente: "",
      tipo_documento: "apolice",
      vigencia_ano: 2026,
      metadata: {}
    )

    expect(filters.to_h).to eq({ ramo: "RCF", tipo_documento: "apolice", vigencia_ano: 2026 })
  end
end
