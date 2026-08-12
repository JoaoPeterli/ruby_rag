require "rails_helper"

RSpec.describe Documents::Pipeline::Steps::Answering::GenerateAnswerStep do
  def prompt_double_class
    @prompt_double_class ||= Struct.new(:messages, keyword_init: true)
  end

  def token_budget_double_class
    @token_budget_double_class ||= Struct.new(:response_budget_tokens, keyword_init: true)
  end

  def unreachable
    Class.new { define_singleton_method(:call) { |**_k| raise "não deveria ser chamado" } }
  end

  def build_context(chat_completion_service: unreachable, chat_stream_service: unreachable, on_delta: nil, token_budget: nil)
    config = Documents::QuestionAnsweringService::Config.new(
      **Documents::QuestionAnsweringService::Config.members.index_with { nil }
    ).with(chat_completion_service: chat_completion_service, chat_stream_service: chat_stream_service)

    context = Documents::Pipeline::AnswerContext.new(
      question: "pergunta", account_id: nil, conversation_history: [],
      config: config, on_delta: on_delta, started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC)
    )
    context.prompt = prompt_double_class.new(messages: [ { role: "user", content: "oi" } ])
    context.token_budget = token_budget
    context
  end

  it "uses chat_completion_service when there is no streaming callback" do
    received = nil
    chat_service = Class.new do
      define_singleton_method(:call) do |**kwargs|
        received = kwargs
        Ai::ChatCompletionService::Result.new(
          content: "resposta", model: "fake-model", finish_reason: "stop",
          usage: {}, prompt_tokens: 1, completion_tokens: 1, total_tokens: 2, duration_ms: 1.0
        )
      end
    end

    context = build_context(chat_completion_service: chat_service)
    Documents::Pipeline::Steps::Answering::GenerateAnswerStep.call(context: context)

    expect(received[:messages]).to eq([ { role: "user", content: "oi" } ])
    expect(context.chat_result.content).to eq("resposta")
  end

  it "uses chat_stream_service and forwards on_delta as the streaming block" do
    forwarded = []
    on_delta = ->(text) { forwarded << text }

    stream_service = Class.new do
      define_singleton_method(:call) do |**_kwargs, &block|
        block.call("pedaço")
        Ai::ChatCompletionService::Result.new(
          content: "resposta completa", model: "fake-model", finish_reason: "stop",
          usage: {}, prompt_tokens: 1, completion_tokens: 1, total_tokens: 2, duration_ms: 1.0
        )
      end
    end

    context = build_context(chat_stream_service: stream_service, on_delta: on_delta)
    Documents::Pipeline::Steps::Answering::GenerateAnswerStep.call(context: context)

    expect(forwarded).to eq([ "pedaço" ])
    expect(context.chat_result.content).to eq("resposta completa")
  end

  it "uses the token budget's response_budget_tokens as max_completion_tokens when present" do
    received = nil
    chat_service = Class.new do
      define_singleton_method(:call) do |**kwargs|
        received = kwargs
        Ai::ChatCompletionService::Result.new(
          content: "x", model: "m", finish_reason: "stop", usage: {},
          prompt_tokens: 1, completion_tokens: 1, total_tokens: 2, duration_ms: 1.0
        )
      end
    end

    context = build_context(chat_completion_service: chat_service, token_budget: token_budget_double_class.new(response_budget_tokens: 321))
    Documents::Pipeline::Steps::Answering::GenerateAnswerStep.call(context: context)

    expect(received[:max_completion_tokens]).to eq(321)
  end

  it "falls back to Ai::Configuration.chat_max_completion_tokens without a token budget" do
    received = nil
    chat_service = Class.new do
      define_singleton_method(:call) do |**kwargs|
        received = kwargs
        Ai::ChatCompletionService::Result.new(
          content: "x", model: "m", finish_reason: "stop", usage: {},
          prompt_tokens: 1, completion_tokens: 1, total_tokens: 2, duration_ms: 1.0
        )
      end
    end

    context = build_context(chat_completion_service: chat_service)
    Documents::Pipeline::Steps::Answering::GenerateAnswerStep.call(context: context)

    expect(received[:max_completion_tokens]).to eq(Ai::Configuration.chat_max_completion_tokens)
  end

  it "wraps chat completion errors as AnswerGenerationError" do
    raising_service = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise Ai::ChatCompletionService::Error, "instável" }
    end

    context = build_context(chat_completion_service: raising_service)

    expect do
      Documents::Pipeline::Steps::Answering::GenerateAnswerStep.call(context: context)
    end.to raise_error(Documents::QuestionAnsweringService::AnswerGenerationError)
  end

  it "does nothing when context.result is already set" do
    context = build_context
    context.result = :already_resolved

    Documents::Pipeline::Steps::Answering::GenerateAnswerStep.call(context: context)

    expect(context.chat_result).to be_nil
  end
end
