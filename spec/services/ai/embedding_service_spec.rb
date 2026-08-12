require "rails_helper"

RSpec.describe Ai::EmbeddingService do
  def fake_http_response_class
    @fake_http_response_class ||= Struct.new(:code, :body)
  end

  # Ai::EmbeddingService não tem gancho de DI e chama Net::HTTP.start
  # diretamente. Substituímos temporariamente o método de classe do
  # Net::HTTP por um fake, sempre restaurando o original depois.
  def with_stubbed_http(response)
    original_method = Net::HTTP.method(:start)
    fake_http = Class.new do
      define_method(:request) { |_request| response }
    end.new

    Net::HTTP.define_singleton_method(:start) do |*_args, **_kwargs, &block|
      block.call(fake_http)
    end

    yield
  ensure
    Net::HTTP.define_singleton_method(:start, original_method)
  end

  it "returns embeddings ordered by the index field in the response" do
    body = {
      data: [
        { index: 1, embedding: [ 0.2, 0.3 ] },
        { index: 0, embedding: [ 0.1, 0.1 ] }
      ]
    }.to_json

    embeddings = with_stubbed_http(fake_http_response_class.new("200", body)) do
      Ai::EmbeddingService.call(texts: [ "ola", "mundo" ])
    end

    expect(embeddings).to eq([ [ 0.1, 0.1 ], [ 0.2, 0.3 ] ])
  end

  it "raises AuthenticationError for an HTTP 401 response" do
    body = { error: { message: "chave inválida" } }.to_json

    expect do
      with_stubbed_http(fake_http_response_class.new("401", body)) do
        Ai::EmbeddingService.call(texts: [ "ola" ])
      end
    end.to raise_error(Ai::EmbeddingService::AuthenticationError)
  end

  it "raises RateLimitError for an HTTP 429 response" do
    expect do
      with_stubbed_http(fake_http_response_class.new("429", "{}")) do
        Ai::EmbeddingService.call(texts: [ "ola" ])
      end
    end.to raise_error(Ai::EmbeddingService::RateLimitError)
  end

  it "raises InvalidResponseError when the embeddings count does not match the texts count" do
    body = { data: [ { index: 0, embedding: [ 0.1 ] } ] }.to_json

    expect do
      with_stubbed_http(fake_http_response_class.new("200", body)) do
        Ai::EmbeddingService.call(texts: [ "ola", "mundo" ])
      end
    end.to raise_error(Ai::EmbeddingService::InvalidResponseError)
  end

  it "raises InvalidResponseError for a malformed embedding value" do
    body = { data: [ { index: 0, embedding: [ "not-a-number" ] } ] }.to_json

    expect do
      with_stubbed_http(fake_http_response_class.new("200", body)) do
        Ai::EmbeddingService.call(texts: [ "ola" ])
      end
    end.to raise_error(Ai::EmbeddingService::InvalidResponseError)
  end

  it "raises InvalidRequestError for an empty text list" do
    expect { Ai::EmbeddingService.call(texts: []) }.to raise_error(Ai::EmbeddingService::InvalidRequestError)
  end

  it "raises InvalidRequestError when one of the texts is blank" do
    expect { Ai::EmbeddingService.call(texts: [ "ola", "   " ]) }.to raise_error(Ai::EmbeddingService::InvalidRequestError)
  end
end
