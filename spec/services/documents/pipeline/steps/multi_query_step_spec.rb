require "rails_helper"

RSpec.describe Documents::Pipeline::Steps::MultiQueryStep do
  def unreachable_service
    Class.new do
      define_singleton_method(:call) { |**_kwargs| raise "não deveria ser chamado" }
    end
  end

  it "skips generation when disabled and builds queries from question and search_query only" do
    context = Documents::Pipeline::Context.new(question: "Qual o prazo?")
    context.search_query = "Qual o prazo da apólice?"
    context.metadata[:multi_query_enabled] = false

    Documents::Pipeline::Steps::MultiQueryStep.call(
      context: context,
      multi_query_service: unreachable_service
    )

    expect(context.queries).to eq([ "Qual o prazo?", "Qual o prazo da apólice?" ])
    expect(context.metadata[:multi_query]).to be_nil
  end

  it "merges the generated queries with the question and search_query, deduplicated" do
    context = Documents::Pipeline::Context.new(question: "Qual o prazo?")
    context.search_query = "Qual o prazo?"
    context.metadata[:multi_query_enabled] = true
    context.metadata[:multi_query_count] = 3

    multi_query = Documents::MultiQueryService::Result.new(
      original_question: "Qual o prazo?",
      queries: [ "prazo de vigência da apólice", "  Qual o prazo?  " ],
      model: "fake-model",
      usage: {},
      duration_ms: 1.0
    )

    service = Class.new do
      define_singleton_method(:call) { |**_kwargs| multi_query }
    end

    Documents::Pipeline::Steps::MultiQueryStep.call(context: context, multi_query_service: service)

    expect(context.queries).to eq([ "Qual o prazo?", "prazo de vigência da apólice" ])
    expect(context.metadata[:multi_query]).to eq(multi_query)
    expect(context.metrics[:multi_query]).to be_a(Numeric)
  end

  it "records a stage failure and still builds a query list when the service errors" do
    context = Documents::Pipeline::Context.new(question: "Qual o prazo?")
    context.search_query = "Qual o prazo da apólice?"
    context.metadata[:multi_query_enabled] = true
    context.metadata[:multi_query_count] = 3

    raising_service = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise Documents::MultiQueryService::GenerationError, "instabilidade" }
    end

    Documents::Pipeline::Steps::MultiQueryStep.call(context: context, multi_query_service: raising_service)

    expect(context.queries).to eq([ "Qual o prazo?", "Qual o prazo da apólice?" ])
    expect(context.metadata[:multi_query]).to be_nil
    expect(context.metadata[:stage_failures].size).to eq(1)
    expect(context.metadata[:stage_failures].first[:stage]).to eq("multi_query")
  end
end
