require "rails_helper"

RSpec.describe Documents::QueryExpansionService do
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

  it "raises for a blank question" do
    expect do
      Documents::QueryExpansionService.call(
        question: "   ",
        chat_completion_service: fake_chat_service(content: "consulta expandida")
      )
    end.to raise_error(Documents::QueryExpansionService::InvalidQuestionError)
  end

  it "returns the expanded query trimmed" do
    result = Documents::QueryExpansionService.call(
      question: "Qual o prazo?",
      chat_completion_service: fake_chat_service(content: "  prazo vigência apólice cobertura  ")
    )

    expect(result.original_question).to eq("Qual o prazo?")
    expect(result.expanded_query).to eq("prazo vigência apólice cobertura")
  end

  it "raises InvalidResponseError when the model returns a blank expansion" do
    expect do
      Documents::QueryExpansionService.call(
        question: "Qual o prazo?",
        chat_completion_service: fake_chat_service(content: "   ")
      )
    end.to raise_error(Documents::QueryExpansionService::InvalidResponseError)
  end

  it "wraps chat completion errors as GenerationError" do
    raising_service = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise Ai::ChatCompletionService::Error, "instabilidade" }
    end

    expect do
      Documents::QueryExpansionService.call(question: "Qual o prazo?", chat_completion_service: raising_service)
    end.to raise_error(Documents::QueryExpansionService::GenerationError, /instabilidade/)
  end

  it "uses the model returned by the completion result over the requested one" do
    result = Documents::QueryExpansionService.call(
      question: "Qual o prazo?",
      model: "modelo-solicitado",
      chat_completion_service: fake_chat_service(content: "expandida", model: "modelo-usado")
    )

    expect(result.model).to eq("modelo-usado")
  end

  it "sends the question as the user message" do
    received = nil

    Documents::QueryExpansionService.call(
      question: "Qual o prazo da apólice?",
      chat_completion_service: fake_chat_service(content: "expandida") { |kwargs| received = kwargs }
    )

    user_message = received[:messages].find { |message| message[:role] == "user" }
    expect(user_message[:content]).to eq("Qual o prazo da apólice?")
  end
end
