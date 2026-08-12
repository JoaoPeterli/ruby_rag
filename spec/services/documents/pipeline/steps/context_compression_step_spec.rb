require "rails_helper"

RSpec.describe Documents::Pipeline::Steps::ContextCompressionStep do
  def result_double_class
    @result_double_class ||= Struct.new(:chunk, keyword_init: true)
  end

  let(:document) { create(:document) }

  def build_chunk(position:, content: "Conteúdo #{position}.")
    document.document_chunks.create!(content: content, position: position, embedding: Array.new(1536, 0.01))
  end

  def build_context(question: "Qual o prazo?", context_chunks: [], results: [], query_embeddings: {}, enabled:, metadata: {})
    context = Documents::Pipeline::Context.new(question: question)
    context.context_chunks = context_chunks
    context.results = results
    context.query_embeddings = query_embeddings
    context.metadata[:context_compression_enabled] = enabled
    metadata.each { |key, value| context.metadata[key] = value }
    context
  end

  def unreachable_service
    Class.new { define_singleton_method(:call) { |**_kwargs| raise "não deveria ser chamado" } }
  end

  it "passes context_chunks through unchanged when compression is disabled" do
    chunks = [ build_chunk(position: 0), build_chunk(position: 1) ]
    context = build_context(context_chunks: chunks, enabled: false)

    Documents::Pipeline::Steps::ContextCompressionStep.call(
      context: context, compression_service: unreachable_service
    )

    expect(context.compressed_chunks).to eq(chunks)
  end

  it "falls back to results chunks when context_chunks is blank" do
    chunk = build_chunk(position: 0)
    context = build_context(context_chunks: [], results: [ result_double_class.new(chunk: chunk) ], enabled: false)

    Documents::Pipeline::Steps::ContextCompressionStep.call(
      context: context, compression_service: unreachable_service
    )

    expect(context.compressed_chunks).to eq([ chunk ])
  end

  it "returns an empty list when enabled but there are no chunks to compress" do
    context = build_context(context_chunks: [], results: [], enabled: true)

    Documents::Pipeline::Steps::ContextCompressionStep.call(
      context: context, compression_service: unreachable_service
    )

    expect(context.compressed_chunks).to be_empty
  end

  it "falls back to the original chunks when no query embedding can be resolved" do
    chunks = [ build_chunk(position: 0) ]
    context = build_context(context_chunks: chunks, enabled: true, query_embeddings: {})

    Documents::Pipeline::Steps::ContextCompressionStep.call(
      context: context, compression_service: unreachable_service
    )

    expect(context.compressed_chunks).to eq(chunks)
  end

  it "compresses using the resolved embedding and records metrics" do
    chunks = [ build_chunk(position: 0), build_chunk(position: 1) ]
    kept = [ chunks.first ]

    compression_result = Documents::ContextCompression::Result.new(
      chunks: kept, removed_chunks: [ chunks.second ], scores: { chunks.first.id => 0.9 },
      original_count: 2, compressed_count: 1, compression_ratio: 0.5,
      duration_ms: 3.0, strategy: "similarity"
    )

    received = nil
    compression_service = Class.new do
      define_singleton_method(:call) { |**kwargs| received = kwargs; compression_result }
    end

    context = build_context(
      question: "Qual o prazo?",
      context_chunks: chunks,
      enabled: true,
      query_embeddings: { "Qual o prazo?" => Array.new(1536, 0.02) },
      metadata: {
        context_compression_max_chunks: 5,
        context_compression_minimum_similarity: 0.5,
        context_compression_preserve_source_chunks: true
      }
    )

    Documents::Pipeline::Steps::ContextCompressionStep.call(context: context, compression_service: compression_service)

    expect(context.compressed_chunks).to eq(kept)
    expect(context.context_compression).to eq(compression_result)
    expect(received[:query_embedding]).to eq(Array.new(1536, 0.02))
    expect(received[:strategy_options][:max_chunks]).to eq(5)
    expect(context.metrics[:context_compression_original_count]).to eq(2)
    expect(context.metrics[:context_compression_compressed_count]).to eq(1)
    expect(context.metrics[:context_compression_removed_count]).to eq(1)
    expect(context.metrics[:context_compression_ratio]).to be_within(0.0001).of(0.5)
    expect(context.metrics[:context_compression_strategy]).to eq("similarity")
  end

  it "falls back to the original chunks and records a stage failure when compression raises" do
    chunks = [ build_chunk(position: 0) ]
    raising_service = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise Documents::ContextCompression::Service::CompressionError, "falha" }
    end

    context = build_context(
      context_chunks: chunks,
      enabled: true,
      query_embeddings: { "Qual o prazo?" => Array.new(1536, 0.02) },
      metadata: {
        context_compression_max_chunks: 5,
        context_compression_minimum_similarity: 0.5,
        context_compression_preserve_source_chunks: true
      }
    )

    Documents::Pipeline::Steps::ContextCompressionStep.call(context: context, compression_service: raising_service)

    expect(context.compressed_chunks).to eq(chunks)
    expect(context.metadata[:stage_failures].size).to eq(1)
    expect(context.metadata[:stage_failures].first[:stage]).to eq("context_compression")
  end
end
