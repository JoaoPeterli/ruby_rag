require "rails_helper"

RSpec.describe Documents::QueryRewriteService do
  def fake_chat_service(content:, model: "fake-model", &on_call)
    Class.new do
      define_singleton_method(:call) do |**kwargs|
        on_call.call(kwargs) if on_call

        Ai::ChatCompletionService::Result.new(
          content: content, model: model, finish_reason: "stop",
          usage: { prompt_tokens: 5, completion_tokens: 5, total_tokens: 10 },
          prompt_tokens: 5, completion_tokens: 5, total_tokens: 10, duration_ms: 1.0
        )
      end
    end
  end

  def unreachable_service
    Class.new do
      define_singleton_method(:call) { |**_kwargs| raise "não deveria ser chamado" }
    end
  end

  it "raises for a blank question" do
    expect do
      Documents::QueryRewriteService.call(question: "  ", history: [], chat_completion_service: unreachable_service)
    end.to raise_error(Documents::QueryRewriteService::InvalidQuestionError)
  end

  it "returns the question unchanged and skips the LLM call when there is no history" do
    result = Documents::QueryRewriteService.call(
      question: "E o prazo?",
      history: [],
      chat_completion_service: unreachable_service
    )

    expect(result.original_question).to eq("E o prazo?")
    expect(result.rewritten_question).to eq("E o prazo?")
    expect(result.rewritten).to be_falsey
    expect(result.model).to be_nil
  end

  it "rewrites the question using the conversation history" do
    history = [
      { role: "user", content: "Qual o prazo da apólice do cliente X?" },
      { role: "assistant", content: "O prazo é de doze meses." }
    ]

    result = Documents::QueryRewriteService.call(
      question: "E a cobertura?",
      history: history,
      chat_completion_service: fake_chat_service(content: "Qual a cobertura da apólice do cliente X?")
    )

    expect(result.original_question).to eq("E a cobertura?")
    expect(result.rewritten_question).to eq("Qual a cobertura da apólice do cliente X?")
    expect(result.rewritten).to be_truthy
  end

  it "marks rewritten as false when the model returns the question unchanged" do
    result = Documents::QueryRewriteService.call(
      question: "Qual o prazo?",
      history: [ { role: "user", content: "oi" } ],
      chat_completion_service: fake_chat_service(content: "Qual o prazo?")
    )

    expect(result.rewritten).to be_falsey
    expect(result.rewritten_question).to eq("Qual o prazo?")
  end

  it "falls back to the original question when the model returns a blank rewrite" do
    result = Documents::QueryRewriteService.call(
      question: "Qual o prazo?",
      history: [ { role: "user", content: "oi" } ],
      chat_completion_service: fake_chat_service(content: "   ")
    )

    expect(result.rewritten_question).to eq("Qual o prazo?")
    expect(result.rewritten).to be_falsey
  end

  it "wraps chat completion errors as GenerationError" do
    raising_service = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise Ai::ChatCompletionService::Error, "instabilidade" }
    end

    expect do
      Documents::QueryRewriteService.call(
        question: "Qual o prazo?",
        history: [ { role: "user", content: "oi" } ],
        chat_completion_service: raising_service
      )
    end.to raise_error(Documents::QueryRewriteService::GenerationError)
  end

  it "only sends the last history_limit turns to the model" do
    history = (1..5).map { |i| { role: "user", content: "turno #{i}" } }
    received = nil

    Documents::QueryRewriteService.call(
      question: "pergunta atual",
      history: history,
      history_limit: 2,
      chat_completion_service: fake_chat_service(content: "reescrita") { |kwargs| received = kwargs }
    )

    user_message = received[:messages].find { |message| message[:role] == "user" }
    expect(user_message[:content]).to include("turno 4")
    expect(user_message[:content]).to include("turno 5")
    expect(user_message[:content]).not_to include("turno 3")
  end
end
