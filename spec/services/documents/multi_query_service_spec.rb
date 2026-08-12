require "rails_helper"

RSpec.describe Documents::MultiQueryService do
  def fake_chat_service(content:, model: "fake-model")
    Class.new do
      define_singleton_method(:call) do |**_kwargs|
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
      Documents::MultiQueryService.call(question: "   ", chat_completion_service: fake_chat_service(content: "x\ny"))
    end.to raise_error(Documents::MultiQueryService::InvalidQuestionError)
  end

  it "raises for a query_count outside 1..8" do
    expect do
      Documents::MultiQueryService.call(
        question: "pergunta",
        query_count: 9,
        chat_completion_service: fake_chat_service(content: "x\ny")
      )
    end.to raise_error(Documents::MultiQueryService::InvalidQueryCountError)
  end

  it "always includes the original question first, followed by the generated queries" do
    content = "Primeira consulta gerada\nSegunda consulta gerada"

    result = Documents::MultiQueryService.call(
      question: "pergunta original",
      chat_completion_service: fake_chat_service(content: content)
    )

    expect(result.original_question).to eq("pergunta original")
    expect(result.queries).to eq([ "pergunta original", "Primeira consulta gerada", "Segunda consulta gerada" ])
  end

  it "strips list markers and numbering from generated lines" do
    content = "- Consulta com traço\n* Consulta com asterisco\n1. Consulta numerada\n2) Consulta numerada parêntese"

    result = Documents::MultiQueryService.call(
      question: "pergunta",
      chat_completion_service: fake_chat_service(content: content)
    )

    expect(result.queries).to eq(
      [ "pergunta", "Consulta com traço", "Consulta com asterisco", "Consulta numerada", "Consulta numerada parêntese" ]
    )
  end

  it "deduplicates queries that only differ by accents, case or punctuation" do
    content = "Qual o PRAZO da apólice?\nqual o prazo da apolice"

    result = Documents::MultiQueryService.call(
      question: "outra pergunta",
      chat_completion_service: fake_chat_service(content: content)
    )

    expect(result.queries).to eq([ "outra pergunta", "Qual o PRAZO da apólice?" ])
  end

  it "truncates to query_count + 1 total queries" do
    content = (1..10).map { |i| "Consulta gerada #{i}" }.join("\n")

    result = Documents::MultiQueryService.call(
      question: "pergunta",
      query_count: 3,
      chat_completion_service: fake_chat_service(content: content)
    )

    expect(result.queries.size).to eq(4)
  end

  it "raises InvalidResponseError when fewer than two distinct queries end up available" do
    expect do
      Documents::MultiQueryService.call(
        question: "pergunta",
        chat_completion_service: fake_chat_service(content: "pergunta")
      )
    end.to raise_error(Documents::MultiQueryService::InvalidResponseError)
  end

  it "wraps chat completion errors as GenerationError" do
    raising_service = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise Ai::ChatCompletionService::Error, "instabilidade" }
    end

    expect do
      Documents::MultiQueryService.call(question: "pergunta", chat_completion_service: raising_service)
    end.to raise_error(Documents::MultiQueryService::GenerationError)
  end

  it "falls back to the requested model when the completion result has none" do
    result = Documents::MultiQueryService.call(
      question: "pergunta",
      model: "modelo-solicitado",
      chat_completion_service: fake_chat_service(content: "a\nb", model: nil)
    )

    expect(result.model).to eq("modelo-solicitado")
  end
end
