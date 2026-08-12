require "rails_helper"

RSpec.describe Documents::QueryRouterService do
  def fake_chat_service(content:, model: "fake-model")
    Class.new do
      define_singleton_method(:call) do |**_kwargs|
        Ai::ChatCompletionService::Result.new(
          content: content,
          model: model,
          finish_reason: "stop",
          usage: { prompt_tokens: 5, completion_tokens: 2, total_tokens: 7 },
          prompt_tokens: 5,
          completion_tokens: 2,
          total_tokens: 7,
          duration_ms: 1.0
        )
      end
    end
  end

  it "classifies the question into the category returned by the model" do
    result = Documents::QueryRouterService.call(
      question: "Qual o prazo da apólice?",
      chat_completion_service: fake_chat_service(
        content: { category: "factual", reason: "Pergunta direta sobre um dado." }.to_json
      )
    )

    expect(result.category).to eq("factual")
    expect(result.reason).to eq("Pergunta direta sobre um dado.")
  end

  it "falls back to factual when the model returns a category outside the known list" do
    result = Documents::QueryRouterService.call(
      question: "Qual o prazo da apólice?",
      chat_completion_service: fake_chat_service(
        content: { category: "categoria_inventada", reason: "x" }.to_json
      )
    )

    expect(result.category).to eq("factual")
  end

  it "strips markdown code fences before parsing the JSON" do
    fenced = "```json\n#{ { category: 'resumo', reason: 'y' }.to_json }\n```"

    result = Documents::QueryRouterService.call(
      question: "Resuma a apólice",
      chat_completion_service: fake_chat_service(content: fenced)
    )

    expect(result.category).to eq("resumo")
  end

  it "raises for a blank question" do
    expect do
      Documents::QueryRouterService.call(
        question: "   ",
        chat_completion_service: fake_chat_service(content: { category: "factual", reason: "x" }.to_json)
      )
    end.to raise_error(Documents::QueryRouterService::InvalidQuestionError)
  end

  it "raises InvalidResponseError for malformed JSON" do
    expect do
      Documents::QueryRouterService.call(
        question: "Qual o prazo da apólice?",
        chat_completion_service: fake_chat_service(content: "isso não é json")
      )
    end.to raise_error(Documents::QueryRouterService::InvalidResponseError)
  end

  it "wraps chat completion errors as GenerationError" do
    raising_service = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise Ai::ChatCompletionService::Error, "instável" }
    end

    expect do
      Documents::QueryRouterService.call(
        question: "Qual o prazo da apólice?",
        chat_completion_service: raising_service
      )
    end.to raise_error(Documents::QueryRouterService::GenerationError, /instável/)
  end

  it "uses the model returned by the completion result, falling back to the requested one" do
    used_model = Documents::QueryRouterService.call(
      question: "Qual o prazo?",
      chat_completion_service: fake_chat_service(
        content: { category: "factual", reason: "x" }.to_json,
        model: "modelo-real"
      )
    ).model
    expect(used_model).to eq("modelo-real")

    fallback_model = Documents::QueryRouterService.call(
      question: "Qual o prazo?",
      model: "modelo-solicitado",
      chat_completion_service: fake_chat_service(
        content: { category: "factual", reason: "x" }.to_json,
        model: nil
      )
    ).model
    expect(fallback_model).to eq("modelo-solicitado")
  end
end
