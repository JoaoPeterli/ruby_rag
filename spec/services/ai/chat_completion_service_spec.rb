require "rails_helper"

RSpec.describe Ai::ChatCompletionService do
  def fake_request_class
    @fake_request_class ||= Struct.new(:headers, :body)
  end

  def fake_response_class
    @fake_response_class ||= Struct.new(:status, :body)
  end

  def build_service(messages: [ { role: "user", content: "Oi" } ], model: "gpt-test", temperature: 0.2, max_completion_tokens: 100)
    Ai::ChatCompletionService.new(
      messages: messages,
      model: model,
      temperature: temperature,
      max_completion_tokens: max_completion_tokens
    )
  end

  # Não há stub de rede embutido nesse nível — fakeamos a fronteira de rede
  # definindo um #connection singleton na instância de teste (descartada
  # depois, nada pra restaurar).
  def stub_connection(service, response)
    request_class = fake_request_class

    fake_connection = Class.new do
      define_method(:post) do |*_args, &block|
        block.call(request_class.new({}, nil)) if block
        response
      end
    end.new

    service.define_singleton_method(:connection) { fake_connection }
    service
  end

  it "parses a successful completion into a Result" do
    body = {
      "model" => "gpt-test-actual",
      "choices" => [ { "message" => { "content" => "Olá!" }, "finish_reason" => "stop" } ],
      "usage" => { "prompt_tokens" => 5, "completion_tokens" => 2, "total_tokens" => 7 }
    }.to_json

    service = stub_connection(build_service, fake_response_class.new(200, body))
    result = service.call

    expect(result.content).to eq("Olá!")
    expect(result.model).to eq("gpt-test-actual")
    expect(result.finish_reason).to eq("stop")
    expect(result.prompt_tokens).to eq(5)
    expect(result.completion_tokens).to eq(2)
    expect(result.total_tokens).to eq(7)
  end

  it "raises RateLimitError for an HTTP 429 response" do
    body = { "error" => { "message" => "limite excedido" } }.to_json
    service = stub_connection(build_service, fake_response_class.new(429, body))

    expect { service.call }.to raise_error(Ai::ChatCompletionService::RateLimitError, /limite excedido/)
  end

  it "raises AuthenticationError for an HTTP 401 response" do
    body = { "error" => { "message" => "chave inválida" } }.to_json
    service = stub_connection(build_service, fake_response_class.new(401, body))

    expect { service.call }.to raise_error(Ai::ChatCompletionService::AuthenticationError)
  end

  it "raises TemporaryError for an HTTP 500 response" do
    service = stub_connection(build_service, fake_response_class.new(500, "{}"))

    expect { service.call }.to raise_error(Ai::ChatCompletionService::TemporaryError)
  end

  it "raises InvalidResponseError when the body has no choices" do
    service = stub_connection(build_service, fake_response_class.new(200, { "choices" => [] }.to_json))

    expect { service.call }.to raise_error(Ai::ChatCompletionService::InvalidResponseError)
  end

  it "wraps a Configuration::ConfigurationError as ConfigurationError" do
    service = build_service
    allow(Ai::Configuration).to receive(:validate!).and_raise(Ai::Configuration::ConfigurationError, "sem chave")

    expect { service.call }.to raise_error(Ai::ChatCompletionService::ConfigurationError, /sem chave/)
  end

  it "raises InvalidRequestError for a blank model" do
    expect { build_service(model: "  ").call }.to raise_error(Ai::ChatCompletionService::InvalidRequestError)
  end

  it "raises InvalidRequestError for an empty messages list" do
    expect { build_service(messages: []).call }.to raise_error(Ai::ChatCompletionService::InvalidRequestError)
  end

  it "raises InvalidRequestError for a message with an invalid role" do
    expect do
      build_service(messages: [ { role: "narrator", content: "Oi" } ]).call
    end.to raise_error(Ai::ChatCompletionService::InvalidRequestError)
  end

  it "raises InvalidRequestError for a message without content" do
    expect do
      build_service(messages: [ { role: "user", content: "" } ]).call
    end.to raise_error(Ai::ChatCompletionService::InvalidRequestError)
  end

  it "raises InvalidRequestError for a temperature outside 0..2" do
    expect { build_service(temperature: 3.0).call }.to raise_error(Ai::ChatCompletionService::InvalidRequestError)
  end

  it "raises InvalidRequestError for a non-positive max_completion_tokens" do
    expect { build_service(max_completion_tokens: 0).call }.to raise_error(Ai::ChatCompletionService::InvalidRequestError)
  end
end
