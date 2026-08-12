require "rails_helper"

RSpec.describe Documents::Pipeline::Steps::ParentDocumentRetrievalStep do
  def chunk_holder_class
    @chunk_holder_class ||= Struct.new(:chunk, keyword_init: true)
  end

  def unreachable_service
    Class.new do
      define_singleton_method(:call) { |**_kwargs| raise "não deveria ser chamado" }
    end
  end

  it "uses the raw chunks from context.results when disabled" do
    context = Documents::Pipeline::Context.new(question: "pergunta")
    context.metadata[:parent_retrieval_enabled] = false
    context.results = [ chunk_holder_class.new(chunk: :chunk_a), chunk_holder_class.new(chunk: :chunk_b) ]

    Documents::Pipeline::Steps::ParentDocumentRetrievalStep.call(
      context: context,
      parent_retrieval_service: unreachable_service
    )

    expect(context.context_chunks).to eq([ :chunk_a, :chunk_b ])
    expect(context.parent_retrieval).to be_nil
  end

  it "returns an empty context when enabled but there are no results" do
    context = Documents::Pipeline::Context.new(question: "pergunta")
    context.metadata[:parent_retrieval_enabled] = true
    context.results = []

    Documents::Pipeline::Steps::ParentDocumentRetrievalStep.call(
      context: context,
      parent_retrieval_service: unreachable_service
    )

    expect(context.context_chunks).to eq([])
  end

  it "stores the parent retrieval result and its chunks when enabled" do
    context = Documents::Pipeline::Context.new(question: "pergunta")
    context.metadata[:parent_retrieval_enabled] = true
    context.metadata[:parent_retrieval_window_size] = 2
    context.metadata[:parent_retrieval_max_chunks] = 20
    context.results = [ chunk_holder_class.new(chunk: :chunk_a) ]

    parent_result = Documents::ParentDocumentRetrievalService::Result.new(
      chunks: [ :chunk_a, :chunk_context ], groups: [], source_chunk_ids: [ 1 ], duration_ms: 1.0
    )
    service = Class.new do
      define_singleton_method(:call) { |**_kwargs| parent_result }
    end

    Documents::Pipeline::Steps::ParentDocumentRetrievalStep.call(
      context: context,
      parent_retrieval_service: service
    )

    expect(context.parent_retrieval).to eq(parent_result)
    expect(context.context_chunks).to eq([ :chunk_a, :chunk_context ])
    expect(context.metrics[:parent_retrieval]).to be_a(Numeric)
  end

  it "records a stage failure and falls back to the raw chunks when the service errors" do
    context = Documents::Pipeline::Context.new(question: "pergunta")
    context.metadata[:parent_retrieval_enabled] = true
    context.metadata[:parent_retrieval_window_size] = 2
    context.metadata[:parent_retrieval_max_chunks] = 20
    context.results = [ chunk_holder_class.new(chunk: :chunk_a) ]

    raising_service = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise Documents::ParentDocumentRetrievalService::RetrievalError, "falha" }
    end

    Documents::Pipeline::Steps::ParentDocumentRetrievalStep.call(
      context: context,
      parent_retrieval_service: raising_service,
      logger: Logger.new(File::NULL)
    )

    expect(context.context_chunks).to eq([ :chunk_a ])
    expect(context.metadata[:stage_failures].size).to eq(1)
    expect(context.metadata[:stage_failures].first[:stage]).to eq("parent_retrieval")
  end
end
