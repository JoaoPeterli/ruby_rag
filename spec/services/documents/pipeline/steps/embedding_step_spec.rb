require "rails_helper"

RSpec.describe Documents::Pipeline::Steps::EmbeddingStep do
  it "maps each query to its embedding and records the elapsed time" do
    context = Documents::Pipeline::Context.new(question: "Qual o prazo?")
    context.queries = [ "Qual o prazo?", "Quais as coberturas?" ]

    embedding_a = Array.new(1536, 0.01)
    embedding_b = Array.new(1536, 0.02)

    received = nil
    embedding_service = Class.new do
      define_singleton_method(:call) { |**kwargs| received = kwargs; [ embedding_a, embedding_b ] }
    end

    Documents::Pipeline::Steps::EmbeddingStep.call(context: context, embedding_service: embedding_service)

    expect(received[:texts]).to eq([ "Qual o prazo?", "Quais as coberturas?" ])
    expect(context.query_embeddings["Qual o prazo?"]).to eq(embedding_a)
    expect(context.query_embeddings["Quais as coberturas?"]).to eq(embedding_b)
    expect(context.metrics[:embedding]).to be >= 0
  end

  it "produces an empty embeddings map when there are no queries" do
    context = Documents::Pipeline::Context.new(question: "Qual o prazo?")
    context.queries = []

    embedding_service = Class.new { define_singleton_method(:call) { |**_kwargs| [] } }

    Documents::Pipeline::Steps::EmbeddingStep.call(context: context, embedding_service: embedding_service)

    expect(context.query_embeddings).to be_empty
  end
end
