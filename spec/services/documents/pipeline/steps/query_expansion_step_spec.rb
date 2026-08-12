require "rails_helper"

RSpec.describe Documents::Pipeline::Steps::QueryExpansionStep do
  def unreachable_service
    Class.new do
      define_singleton_method(:call) { |**_kwargs| raise "não deveria ser chamado" }
    end
  end

  it "leaves search_query untouched when disabled" do
    context = Documents::Pipeline::Context.new(question: "Qual o prazo?")

    Documents::Pipeline::Steps::QueryExpansionStep.call(
      context: context,
      query_expansion_service: unreachable_service
    )

    expect(context.search_query).to eq("Qual o prazo?")
    expect(context.expanded_query).to be_nil
  end

  it "expands the search_query and stores the expansion when enabled" do
    context = Documents::Pipeline::Context.new(question: "Qual o prazo?")
    context.metadata[:query_expansion_enabled] = true

    expansion = Documents::QueryExpansionService::Result.new(
      original_question: "Qual o prazo?",
      expanded_query: "prazo vigência apólice cobertura",
      model: "fake-model",
      usage: {},
      duration_ms: 1.0
    )
    service = Class.new do
      define_singleton_method(:call) { |**_kwargs| expansion }
    end

    Documents::Pipeline::Steps::QueryExpansionStep.call(context: context, query_expansion_service: service)

    expect(context.expanded_query).to eq(expansion)
    expect(context.search_query).to eq("prazo vigência apólice cobertura")
    expect(context.metrics[:query_expansion]).to be_a(Numeric)
  end

  it "records a stage failure and resets search_query to the question when the service errors" do
    context = Documents::Pipeline::Context.new(question: "Qual o prazo?")
    context.search_query = "estado anterior irrelevante"
    context.metadata[:query_expansion_enabled] = true

    raising_service = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise Documents::QueryExpansionService::GenerationError, "instabilidade" }
    end

    Documents::Pipeline::Steps::QueryExpansionStep.call(context: context, query_expansion_service: raising_service)

    expect(context.search_query).to eq("Qual o prazo?")
    expect(context.metadata[:stage_failures].size).to eq(1)
    expect(context.metadata[:stage_failures].first[:stage]).to eq("query_expansion")
  end
end
