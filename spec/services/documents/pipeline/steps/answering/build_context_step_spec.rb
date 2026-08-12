require "rails_helper"

RSpec.describe Documents::Pipeline::Steps::Answering::BuildContextStep do
  def search_result_double_class
    @search_result_double_class ||= Struct.new(:chunk, :distance, :similarity, keyword_init: true)
  end

  def retrieval_result_double_class
    @retrieval_result_double_class ||= Struct.new(:results, :context_chunks, :compressed_chunks, keyword_init: true)
  end

  def token_budget_double_class
    @token_budget_double_class ||= Struct.new(:context_budget_characters, keyword_init: true)
  end

  let(:document) { create(:document) }

  def build_chunk(position:, content: "Conteúdo #{position}.")
    document.document_chunks.create!(content: content, position: position, embedding: Array.new(1536, 0.01))
  end

  def build_context(retrieval_result:, token_budget: nil, context_builder:)
    config = Documents::QuestionAnsweringService::Config.new(
      **Documents::QuestionAnsweringService::Config.members.index_with { nil }
    ).with(context_builder: context_builder)

    context = Documents::Pipeline::AnswerContext.new(
      question: "pergunta", account_id: nil, conversation_history: [],
      config: config, on_delta: nil, started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC)
    )
    context.retrieval_result = retrieval_result
    context.token_budget = token_budget
    context
  end

  def fake_builder(&on_call)
    canned = Documents::ContextBuilder::Result.new(
      context: "contexto montado", sources: [], chunks_count: 0, characters_count: 0,
      truncated: false, input_chunks_count: 0, discarded_chunks_count: 0
    )

    Class.new do
      define_singleton_method(:call) do |**kwargs|
        on_call.call(kwargs) if on_call
        canned
      end
    end
  end

  it "prefers compressed_chunks and forwards them as VectorSearchResult with the matching search score" do
    chunk = build_chunk(position: 0)
    search_result = search_result_double_class.new(chunk: chunk, distance: 0.1, similarity: 0.8)
    retrieval_result = retrieval_result_double_class.new(
      results: [ search_result ], context_chunks: [], compressed_chunks: [ chunk ]
    )

    received = nil
    context = build_context(retrieval_result: retrieval_result, context_builder: fake_builder { |kwargs| received = kwargs })
    Documents::Pipeline::Steps::Answering::BuildContextStep.call(context: context)

    expect(received[:results].size).to eq(1)
    result = received[:results].first
    expect(result).to be_a(Documents::VectorSearchResult)
    expect(result.chunk_id).to eq(chunk.id)
    expect(result.score).to be_within(0.0001).of(0.8)
    expect(received.key?(:max_characters)).to be_falsey
    expect(context.context_result.context).to eq("contexto montado")
  end

  it "falls back to context_chunks when compressed_chunks is blank" do
    chunk = build_chunk(position: 0)
    search_result = search_result_double_class.new(chunk: chunk, distance: 0.2, similarity: 0.5)
    retrieval_result = retrieval_result_double_class.new(
      results: [ search_result ], context_chunks: [ chunk ], compressed_chunks: []
    )

    received = nil
    context = build_context(retrieval_result: retrieval_result, context_builder: fake_builder { |kwargs| received = kwargs })
    Documents::Pipeline::Steps::Answering::BuildContextStep.call(context: context)

    expect(received[:results].map(&:chunk_id)).to eq([ chunk.id ])
  end

  it "falls back to the chunks referenced by results when both chunk lists are blank" do
    chunk = build_chunk(position: 0)
    search_result = search_result_double_class.new(chunk: chunk, distance: 0.3, similarity: 0.4)
    retrieval_result = retrieval_result_double_class.new(
      results: [ search_result ], context_chunks: [], compressed_chunks: []
    )

    received = nil
    context = build_context(retrieval_result: retrieval_result, context_builder: fake_builder { |kwargs| received = kwargs })
    Documents::Pipeline::Steps::Answering::BuildContextStep.call(context: context)

    expect(received[:results].map(&:chunk_id)).to eq([ chunk.id ])
  end

  it "defaults to a score of zero when a chunk has no matching search result" do
    chunk = build_chunk(position: 0)
    retrieval_result = retrieval_result_double_class.new(results: [], context_chunks: [], compressed_chunks: [ chunk ])

    received = nil
    context = build_context(retrieval_result: retrieval_result, context_builder: fake_builder { |kwargs| received = kwargs })
    Documents::Pipeline::Steps::Answering::BuildContextStep.call(context: context)

    result = received[:results].first
    expect(result.score).to be_within(0.0001).of(0.0)
    expect(result.distance).to be_nil
  end

  it "passes the token budget's context_budget_characters as max_characters when present" do
    chunk = build_chunk(position: 0)
    retrieval_result = retrieval_result_double_class.new(results: [], context_chunks: [], compressed_chunks: [ chunk ])
    token_budget = token_budget_double_class.new(context_budget_characters: 4000)

    received = nil
    context = build_context(
      retrieval_result: retrieval_result, token_budget: token_budget,
      context_builder: fake_builder { |kwargs| received = kwargs }
    )
    Documents::Pipeline::Steps::Answering::BuildContextStep.call(context: context)

    expect(received[:max_characters]).to eq(4000)
  end

  it "wraps context builder failures as ContextBuildError" do
    chunk = build_chunk(position: 0)
    retrieval_result = retrieval_result_double_class.new(results: [], context_chunks: [], compressed_chunks: [ chunk ])

    raising_builder = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise Documents::ContextBuilder::Error, "sem fontes" }
    end

    context = build_context(retrieval_result: retrieval_result, context_builder: raising_builder)

    expect do
      Documents::Pipeline::Steps::Answering::BuildContextStep.call(context: context)
    end.to raise_error(Documents::QuestionAnsweringService::ContextBuildError)
  end

  it "does nothing when context.result is already set" do
    context = build_context(
      retrieval_result: retrieval_result_double_class.new(results: [], context_chunks: [], compressed_chunks: []),
      context_builder: Class.new { define_singleton_method(:call) { |**_k| raise "não deveria ser chamado" } }
    )
    context.result = :already_resolved

    Documents::Pipeline::Steps::Answering::BuildContextStep.call(context: context)

    expect(context.context_result).to be_nil
  end
end
