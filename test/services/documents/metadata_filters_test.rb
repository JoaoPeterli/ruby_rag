require "test_helper"

class Documents::MetadataFiltersTest < ActiveSupport::TestCase
  test "empty returns a filter with every field blank" do
    filters = Documents::MetadataFilters.empty

    assert filters.empty?
    assert_equal({}, filters.metadata)
  end

  test "empty? is false when any field is present" do
    filters = Documents::MetadataFilters.empty.with(ramo: "RCF")

    assert_not filters.empty?
  end

  test "to_h drops blank fields" do
    filters = Documents::MetadataFilters.new(
      ramo: "RCF",
      seguradora: nil,
      cliente: "",
      tipo_documento: "apolice",
      vigencia_ano: 2026,
      metadata: {}
    )

    assert_equal(
      { ramo: "RCF", tipo_documento: "apolice", vigencia_ano: 2026 },
      filters.to_h
    )
  end
end
