require "rails_helper"

RSpec.describe Ai::ChatService do
  # Ai::ChatService não tem gancho de injeção de dependência — chama a
  # constante global OPENAI_CLIENT diretamente (definida em
  # config/initializers/openai.rb). Trocamos essa constante por um
  # cliente fake durante cada exemplo, sempre restaurando o original.
  def with_stubbed_client(client)
    original = OPENAI_CLIENT
    Object.send(:remove_const, :OPENAI_CLIENT)
    Object.const_set(:OPENAI_CLIENT, client)

    yield
  ensure
    Object.send(:remove_const, :OPENAI_CLIENT)
    Object.const_set(:OPENAI_CLIENT, original)
  end

  def build_client(output_text: nil, error: nil, &on_create)
    responses = Class.new do
      define_method(:create) do |**kwargs|
        on_create.call(kwargs) if on_create
        raise error if error

        Struct.new(:output_text).new(output_text)
      end
    end.new

    Class.new do
      define_method(:responses) { responses }
    end.new
  end

  it "returns the output_text from a successful response" do
    client = build_client(output_text: "Resposta gerada pela IA.")

    result = with_stubbed_client(client) { Ai::ChatService.call("Qual o prazo da apólice?") }

    expect(result).to eq("Resposta gerada pela IA.")
  end

  it "sends the given prompt and the configured model to the client" do
    received = nil
    client = build_client(output_text: "ok") { |kwargs| received = kwargs }

    with_stubbed_client(client) { Ai::ChatService.call("minha pergunta") }

    expect(received[:input]).to eq("minha pergunta")
    expect(received[:model]).to eq(Ai::ChatService::MODEL)
  end

  it "wraps any underlying error as Ai::ChatService::Error" do
    client = build_client(error: RuntimeError.new("timeout na API"))

    expect do
      with_stubbed_client(client) { Ai::ChatService.call("pergunta") }
    end.to raise_error(Ai::ChatService::Error)
  end
end
