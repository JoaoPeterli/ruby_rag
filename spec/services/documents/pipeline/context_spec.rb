require "rails_helper"

RSpec.describe Documents::Pipeline::Context do
  it "initializes with the question echoed into search_query and empty collections everywhere else" do
    context = Documents::Pipeline::Context.new(question: "Qual o prazo da apólice?")

    expect(context.question).to eq("Qual o prazo da apólice?")
    expect(context.search_query).to eq("Qual o prazo da apólice?")
    expect(context.queries).to eq([])
    expect(context.query_embeddings).to eq({})
    expect(context.metadata_filters).to eq(Documents::MetadataFilters.empty)
    expect(context.metadata_extraction).to be_nil
    expect(context.vector_results).to eq({})
    expect(context.text_results).to eq({})
    expect(context.hybrid_results).to eq({})
    expect(context.merged_results).to eq([])
    expect(context.reranked_results).to eq([])
    expect(context.cross_encoder).to be_nil
    expect(context.cross_encoder_results).to eq([])
    expect(context.results).to eq([])
    expect(context.parent_retrieval).to be_nil
    expect(context.context_chunks).to eq([])
    expect(context.context_compression).to be_nil
    expect(context.compressed_chunks).to eq([])
    expect(context.metadata).to eq({})
    expect(context.metrics).to eq({})
  end

  it "keeps every attribute mutable after construction" do
    context = Documents::Pipeline::Context.new(question: "pergunta")

    context.search_query = "pergunta reescrita"
    context.results << :some_result
    context.metrics[:hybrid_search] = 12.3

    expect(context.search_query).to eq("pergunta reescrita")
    expect(context.results).to eq([ :some_result ])
    expect(context.metrics[:hybrid_search]).to eq(12.3)
  end
end
