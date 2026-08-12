require "rails_helper"

RSpec.describe Documents::MetadataExtractionService do
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
      Documents::MetadataExtractionService.call(
        question: "   ",
        chat_completion_service: fake_chat_service(content: "{}")
      )
    end.to raise_error(Documents::MetadataExtractionService::InvalidQuestionError)
  end

  it "extracts only the allowed fields, dropping anything else the model returns" do
    content = { ramo: "auto", seguradora: "Acme Seguros", ano_arbitrario: "2030" }.to_json

    result = Documents::MetadataExtractionService.call(
      question: "apólices de auto da Acme",
      chat_completion_service: fake_chat_service(content: content)
    )

    expect(result.filters.ramo).to eq("auto")
    expect(result.filters.seguradora).to eq("Acme Seguros")
    expect(result.filters.cliente).to be_nil
  end

  it "normalizes blank field values to nil" do
    content = { ramo: "  ", seguradora: "Acme" }.to_json

    result = Documents::MetadataExtractionService.call(
      question: "pergunta",
      chat_completion_service: fake_chat_service(content: content)
    )

    expect(result.filters.ramo).to be_nil
    expect(result.filters.seguradora).to eq("Acme")
  end

  it "parses vigencia_ano as an integer within a plausible range" do
    content = { vigencia_ano: "2030" }.to_json

    result = Documents::MetadataExtractionService.call(
      question: "pergunta",
      chat_completion_service: fake_chat_service(content: content)
    )

    expect(result.filters.vigencia_ano).to eq(2030)
  end

  it "discards vigencia_ano when it falls outside the plausible range or is not a number" do
    out_of_range = Documents::MetadataExtractionService.call(
      question: "pergunta",
      chat_completion_service: fake_chat_service(content: { vigencia_ano: "1500" }.to_json)
    )
    expect(out_of_range.filters.vigencia_ano).to be_nil

    garbage = Documents::MetadataExtractionService.call(
      question: "pergunta",
      chat_completion_service: fake_chat_service(content: { vigencia_ano: "não é ano" }.to_json)
    )
    expect(garbage.filters.vigencia_ano).to be_nil
  end

  it "strips markdown code fences before parsing" do
    fenced = "```json\n#{ { ramo: 'auto' }.to_json }\n```"

    result = Documents::MetadataExtractionService.call(
      question: "pergunta",
      chat_completion_service: fake_chat_service(content: fenced)
    )

    expect(result.filters.ramo).to eq("auto")
  end

  it "raises InvalidResponseError when the model does not return a JSON object" do
    expect do
      Documents::MetadataExtractionService.call(
        question: "pergunta",
        chat_completion_service: fake_chat_service(content: "[1, 2, 3]")
      )
    end.to raise_error(Documents::MetadataExtractionService::InvalidResponseError)
  end

  it "wraps chat completion errors as GenerationError" do
    raising_service = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise Ai::ChatCompletionService::Error, "instabilidade" }
    end

    expect do
      Documents::MetadataExtractionService.call(question: "pergunta", chat_completion_service: raising_service)
    end.to raise_error(Documents::MetadataExtractionService::GenerationError)
  end

  it "falls back to the requested model when the completion result has none" do
    result = Documents::MetadataExtractionService.call(
      question: "pergunta",
      model: "modelo-solicitado",
      chat_completion_service: fake_chat_service(content: "{}", model: nil)
    )

    expect(result.model).to eq("modelo-solicitado")
  end
end
