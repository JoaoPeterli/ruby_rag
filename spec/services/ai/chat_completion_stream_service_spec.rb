require "rails_helper"

RSpec.describe Ai::ChatCompletionStreamService do
  def fake_options_class
    @fake_options_class ||= Struct.new(:on_data)
  end

  def fake_request_class
    return @fake_request_class if @fake_request_class

    options_class = fake_options_class

    @fake_request_class = Struct.new(:headers, :options, :body) do
      define_method(:initialize) do |*args|
        super(*args)
        self.headers ||= {}
        self.options ||= options_class.new
      end
    end
  end

  def fake_response_class
    @fake_response_class ||= Struct.new(:status, :body)
  end

  def build_service(messages: [ { role: "user", content: "Oi" } ], &on_delta)
    Ai::ChatCompletionStreamService.new(messages: messages, &on_delta)
  end

  # Não há stub de rede embutido nesse nível — fakeamos a fronteira de rede
  # definindo um #connection singleton na instância de teste (descartada
  # depois, nada pra restaurar), alimentando eventos SSE sintéticos direto
  # em request.options.on_data.
  def stub_streamed_connection(service, events:, final_status: 200)
    request_class = fake_request_class
    response_class = fake_response_class

    fake_connection = Class.new do
      define_method(:post) do |*_args, &block|
        request = request_class.new
        block.call(request)

        events.each do |event|
          data = "data: #{event.to_json}\n\n"
          request.options.on_data.call(data, data.bytesize)
        end

        request.options.on_data.call("data: [DONE]\n\n", 14)

        response_class.new(final_status, "")
      end
    end.new

    service.define_singleton_method(:connection) { fake_connection }
    service
  end

  it "accumulates streamed deltas, calls the block, and returns the final Result" do
    received_deltas = []

    service = build_service { |delta| received_deltas << delta }

    stub_streamed_connection(
      service,
      events: [
        { choices: [ { delta: { content: "Olá" } } ] },
        {
          choices: [ { delta: { content: "!" }, finish_reason: "stop" } ],
          model: "gpt-test-actual",
          usage: { prompt_tokens: 5, completion_tokens: 2, total_tokens: 7 }
        }
      ]
    )

    result = service.call

    expect(received_deltas).to eq([ "Olá", "!" ])
    expect(result.content).to eq("Olá!")
    expect(result.model).to eq("gpt-test-actual")
    expect(result.finish_reason).to eq("stop")
    expect(result.total_tokens).to eq(7)
  end

  it "works without an on_delta block" do
    service = build_service

    stub_streamed_connection(
      service,
      events: [ { choices: [ { delta: { content: "Oi" }, finish_reason: "stop" } ] } ]
    )

    result = service.call

    expect(result.content).to eq("Oi")
  end

  it "falls back to the requested model when no model arrives in the stream" do
    service = build_service

    stub_streamed_connection(
      service,
      events: [ { choices: [ { delta: { content: "Oi" }, finish_reason: "stop" } ] } ]
    )

    result = service.call

    expect(Ai::Configuration.chat_model).to eq("gpt-4.1-mini")
    expect(result.model).to eq(Ai::Configuration.chat_model)
  end

  it "raises InvalidRequestError for an empty messages list" do
    expect { build_service(messages: []).call }.to raise_error(Ai::ChatCompletionStreamService::InvalidRequestError)
  end

  it "raises InvalidRequestError for a message with an invalid role" do
    expect do
      build_service(messages: [ { role: "narrator", content: "Oi" } ]).call
    end.to raise_error(Ai::ChatCompletionStreamService::InvalidRequestError)
  end
end
