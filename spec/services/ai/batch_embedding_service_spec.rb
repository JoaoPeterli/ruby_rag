require "rails_helper"

RSpec.describe Ai::BatchEmbeddingService do
  def fake_embedding_service(&block)
    Class.new do
      define_singleton_method(:call) { |**kwargs| block.call(kwargs) }
    end
  end

  it "splits texts into batches and concatenates the embeddings in order" do
    calls = []

    embedding_service = fake_embedding_service do |kwargs|
      calls << kwargs[:texts]
      kwargs[:texts].map { |text| [ text.length.to_f ] }
    end

    result = Ai::BatchEmbeddingService.call(
      texts: %w[um dois tres quatro cinco],
      batch_size: 2,
      embedding_service: embedding_service
    )

    expect(calls).to eq([ %w[um dois], %w[tres quatro], %w[cinco] ])
    expect(result.requests_count).to eq(3)
    expect(result.texts_count).to eq(5)
    expect(result.embeddings).to eq([ [ 2.0 ], [ 4.0 ], [ 4.0 ], [ 6.0 ], [ 5.0 ] ])
  end

  it "strips whitespace from every text before sending" do
    received = nil

    embedding_service = fake_embedding_service do |kwargs|
      received = kwargs[:texts]
      kwargs[:texts].map { [ 0.0 ] }
    end

    Ai::BatchEmbeddingService.call(
      texts: [ "  ola  ", "mundo\n" ],
      batch_size: 10,
      embedding_service: embedding_service
    )

    expect(received).to eq(%w[ola mundo])
  end

  it "raises for an empty text list" do
    expect do
      Ai::BatchEmbeddingService.call(texts: [], batch_size: 10, embedding_service: fake_embedding_service { |_| [] })
    end.to raise_error(Ai::BatchEmbeddingService::InvalidInputError)
  end

  it "raises when one of the texts is blank" do
    expect do
      Ai::BatchEmbeddingService.call(
        texts: [ "ola", "   " ],
        batch_size: 10,
        embedding_service: fake_embedding_service { |kwargs| kwargs[:texts].map { [ 0.0 ] } }
      )
    end.to raise_error(Ai::BatchEmbeddingService::InvalidInputError)
  end

  it "raises for a non-positive batch_size" do
    expect do
      Ai::BatchEmbeddingService.call(
        texts: [ "ola" ],
        batch_size: 0,
        embedding_service: fake_embedding_service { |kwargs| kwargs[:texts].map { [ 0.0 ] } }
      )
    end.to raise_error(Ai::BatchEmbeddingService::InvalidInputError)
  end

  it "raises when a batch returns a mismatched number of embeddings" do
    embedding_service = fake_embedding_service { |_kwargs| [ [ 0.0 ] ] }

    expect do
      Ai::BatchEmbeddingService.call(
        texts: %w[um dois],
        batch_size: 2,
        embedding_service: embedding_service
      )
    end.to raise_error(Ai::BatchEmbeddingService::ResultMismatchError)
  end

  it "raises when the embedding service does not return an Array" do
    embedding_service = fake_embedding_service { |_kwargs| nil }

    expect do
      Ai::BatchEmbeddingService.call(texts: [ "ola" ], batch_size: 10, embedding_service: embedding_service)
    end.to raise_error(Ai::BatchEmbeddingService::ResultMismatchError)
  end

  it "uses Ai::Configuration::EMBEDDING_BATCH_SIZE as the default batch_size" do
    result = Ai::BatchEmbeddingService.call(
      texts: [ "ola" ], embedding_service: fake_embedding_service { |kwargs| kwargs[:texts].map { [ 0.0 ] } }
    )

    expect(result.batch_size).to eq(Ai::Configuration::EMBEDDING_BATCH_SIZE)
  end
end
