require "rails_helper"

RSpec.describe Documents::Pipeline::Steps::MetadataExtractionStep do
  def unreachable_service
    Class.new do
      define_singleton_method(:call) { |**_kwargs| raise "não deveria ser chamado" }
    end
  end

  it "skips extraction and clears filters when disabled" do
    context = Documents::Pipeline::Context.new(question: "pergunta")
    context.metadata[:metadata_extraction_enabled] = false
    context.metadata_filters = Documents::MetadataFilters.new(
      ramo: "auto", seguradora: nil, cliente: nil, tipo_documento: nil, vigencia_ano: nil, metadata: {}
    )

    Documents::Pipeline::Steps::MetadataExtractionStep.call(
      context: context,
      metadata_extraction_service: unreachable_service
    )

    expect(context.metadata_filters.empty?).to be_truthy
    expect(context.metrics[:metadata_extraction]).to be_nil
  end

  it "stores the extraction result and its filters when enabled" do
    context = Documents::Pipeline::Context.new(question: "pergunta sobre apólice")
    context.metadata[:metadata_extraction_enabled] = true

    filters = Documents::MetadataFilters.new(
      ramo: "auto", seguradora: nil, cliente: nil, tipo_documento: nil, vigencia_ano: nil, metadata: {}
    )
    extraction = Documents::MetadataExtractionService::Result.new(
      filters: filters, raw_content: "{}", model: "fake-model", usage: {}, duration_ms: 1.0
    )

    service = Class.new do
      define_singleton_method(:call) { |**_kwargs| extraction }
    end

    Documents::Pipeline::Steps::MetadataExtractionStep.call(
      context: context,
      metadata_extraction_service: service
    )

    expect(context.metadata_extraction).to eq(extraction)
    expect(context.metadata_filters).to eq(filters)
    expect(context.metrics[:metadata_extraction]).to be_a(Numeric)
  end

  it "records a stage failure and falls back to empty filters when the service errors" do
    context = Documents::Pipeline::Context.new(question: "pergunta")
    context.metadata[:metadata_extraction_enabled] = true

    raising_service = Class.new do
      define_singleton_method(:call) do |**_kwargs|
        raise Documents::MetadataExtractionService::GenerationError, "instabilidade"
      end
    end

    Documents::Pipeline::Steps::MetadataExtractionStep.call(
      context: context,
      metadata_extraction_service: raising_service,
      logger: Logger.new(File::NULL)
    )

    expect(context.metadata_filters.empty?).to be_truthy
    expect(context.metadata[:stage_failures].size).to eq(1)
    expect(context.metadata[:stage_failures].first[:stage]).to eq("metadata_extraction")
  end
end
