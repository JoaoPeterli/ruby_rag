require "rails_helper"

RSpec.describe Documents::HallucinationCheckService do
  def fake_chat_service(content:, model: "fake-model", &on_call)
    Class.new do
      define_singleton_method(:call) do |**kwargs|
        on_call.call(kwargs) if on_call

        Ai::ChatCompletionService::Result.new(
          content: content,
          model: model,
          finish_reason: "stop",
          usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
          prompt_tokens: 10,
          completion_tokens: 5,
          total_tokens: 15,
          duration_ms: 1.0
        )
      end
    end
  end

  def verdicts_json(claims)
    { claims: claims }.to_json
  end

  it "raises for a blank answer" do
    expect do
      Documents::HallucinationCheckService.call(
        question: "Qual o prazo?",
        answer: "   ",
        context: "O prazo é de doze meses.",
        chat_completion_service: fake_chat_service(content: verdicts_json([]))
      )
    end.to raise_error(Documents::HallucinationCheckService::InvalidAnswerError)
  end

  it "raises for a blank context" do
    expect do
      Documents::HallucinationCheckService.call(
        question: "Qual o prazo?",
        answer: "O prazo é de doze meses.",
        context: "",
        chat_completion_service: fake_chat_service(content: verdicts_json([]))
      )
    end.to raise_error(Documents::HallucinationCheckService::InvalidContextError)
  end

  it "computes hallucination_rate and hallucinated? from mixed verdicts" do
    content = verdicts_json([
      { claim: "O prazo é de doze meses", supported: true, reason: "Consta no contexto" },
      { claim: "A apólice cobre roubo", supported: true, reason: "Consta no contexto" },
      { claim: "A apólice cobre incêndio", supported: false, reason: "Não consta no contexto" }
    ])

    result = Documents::HallucinationCheckService.call(
      question: "Quais as condições da apólice?",
      answer: "O prazo é de doze meses, cobre roubo e incêndio.",
      context: "O prazo é de doze meses. A apólice cobre roubo.",
      chat_completion_service: fake_chat_service(content: content)
    )

    expect(result.verdicts.size).to eq(3)
    expect(result.supported_count).to eq(2)
    expect(result.unsupported_count).to eq(1)
    expect(result.hallucination_rate).to be_within(0.0001).of(0.3333)
    expect(result.hallucinated?).to be_truthy
  end

  it "has zero hallucination_rate and hallucinated? false when every claim is supported" do
    content = verdicts_json([
      { claim: "O prazo é de doze meses", supported: true, reason: "Consta no contexto" }
    ])

    result = Documents::HallucinationCheckService.call(
      question: "Qual o prazo?",
      answer: "O prazo é de doze meses.",
      context: "O prazo é de doze meses.",
      chat_completion_service: fake_chat_service(content: content)
    )

    expect(result.hallucination_rate).to eq(0.0)
    expect(result.hallucinated?).to be_falsey
  end

  it "has zero hallucination_rate when there are no verifiable claims" do
    result = Documents::HallucinationCheckService.call(
      question: "Qual o prazo?",
      answer: "Não encontrei informações suficientes.",
      context: "O prazo é de doze meses.",
      chat_completion_service: fake_chat_service(content: verdicts_json([]))
    )

    expect(result.verdicts).to be_empty
    expect(result.hallucination_rate).to eq(0.0)
    expect(result.hallucinated?).to be_falsey
  end

  it "strips markdown code fences before parsing the JSON" do
    fenced = "```json\n#{verdicts_json([ { claim: 'x', supported: true, reason: 'y' } ])}\n```"

    result = Documents::HallucinationCheckService.call(
      question: "Qual o prazo?",
      answer: "O prazo é de doze meses.",
      context: "O prazo é de doze meses.",
      chat_completion_service: fake_chat_service(content: fenced)
    )

    expect(result.supported_count).to eq(1)
  end

  it "raises InvalidResponseError when the model returns invalid JSON" do
    expect do
      Documents::HallucinationCheckService.call(
        question: "Qual o prazo?",
        answer: "O prazo é de doze meses.",
        context: "O prazo é de doze meses.",
        chat_completion_service: fake_chat_service(content: "isso não é um JSON")
      )
    end.to raise_error(Documents::HallucinationCheckService::InvalidResponseError)
  end

  it "raises InvalidResponseError when the JSON has no claims array" do
    expect do
      Documents::HallucinationCheckService.call(
        question: "Qual o prazo?",
        answer: "O prazo é de doze meses.",
        context: "O prazo é de doze meses.",
        chat_completion_service: fake_chat_service(content: { foo: "bar" }.to_json)
      )
    end.to raise_error(Documents::HallucinationCheckService::InvalidResponseError)
  end

  it "wraps chat completion errors as GenerationError" do
    raising_service = Class.new do
      define_singleton_method(:call) do |**_kwargs|
        raise Ai::ChatCompletionService::Error, "instabilidade na API"
      end
    end

    expect do
      Documents::HallucinationCheckService.call(
        question: "Qual o prazo?",
        answer: "O prazo é de doze meses.",
        context: "O prazo é de doze meses.",
        chat_completion_service: raising_service
      )
    end.to raise_error(Documents::HallucinationCheckService::GenerationError, /instabilidade na API/)
  end

  it "uses the model returned by the completion result over the requested one" do
    result = Documents::HallucinationCheckService.call(
      question: "Qual o prazo?",
      answer: "O prazo é de doze meses.",
      context: "O prazo é de doze meses.",
      model: "modelo-solicitado",
      chat_completion_service: fake_chat_service(
        content: verdicts_json([]),
        model: "modelo-realmente-usado"
      )
    )

    expect(result.model).to eq("modelo-realmente-usado")
  end

  it "falls back to the requested model when the completion result has none" do
    result = Documents::HallucinationCheckService.call(
      question: "Qual o prazo?",
      answer: "O prazo é de doze meses.",
      context: "O prazo é de doze meses.",
      model: "modelo-solicitado",
      chat_completion_service: fake_chat_service(content: verdicts_json([]), model: nil)
    )

    expect(result.model).to eq("modelo-solicitado")
  end

  it "sends the question, context and answer to the chat completion service" do
    received = nil

    Documents::HallucinationCheckService.call(
      question: "Qual o prazo da apólice?",
      answer: "O prazo é de doze meses.",
      context: "A apólice tem vigência de doze meses.",
      chat_completion_service: fake_chat_service(content: verdicts_json([])) { |kwargs| received = kwargs }
    )

    user_message = received[:messages].find { |message| message[:role] == "user" }

    expect(user_message[:content]).to include("Qual o prazo da apólice?")
    expect(user_message[:content]).to include("A apólice tem vigência de doze meses.")
    expect(user_message[:content]).to include("O prazo é de doze meses.")
  end
end
