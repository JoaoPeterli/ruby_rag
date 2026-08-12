require "rails_helper"

RSpec.describe Documents::ContextCompression::Service do
  def chunk_double_class
    @chunk_double_class ||= Struct.new(:id)
  end

  def fake_strategy(&block)
    Class.new do
      define_singleton_method(:name) { "FakeStrategy" }
      define_singleton_method(:call) { |**kwargs| block.call(kwargs) }
    end
  end

  it "builds a Result from the strategy output, computing removed chunks and compression_ratio" do
    kept = chunk_double_class.new(1)
    removed = chunk_double_class.new(2)

    strategy = fake_strategy { |_kwargs| { chunks: [ kept ], scores: { 1 => { similarity: 0.9 } } } }

    result = Documents::ContextCompression::Service.call(
      question: "pergunta",
      chunks: [ kept, removed ],
      query_embedding: [ 0.1 ],
      strategy: strategy
    )

    expect(result.chunks).to eq([ kept ])
    expect(result.removed_chunks).to eq([ removed ])
    expect(result.original_count).to eq(2)
    expect(result.compressed_count).to eq(1)
    expect(result.compression_ratio).to be_within(0.0001).of(0.5)
    expect(result.strategy).to eq("FakeStrategy")
    expect(result.compressed?).to be_truthy
  end

  it "compression_ratio is zero when there are no input chunks" do
    strategy = fake_strategy { |_kwargs| { chunks: [], scores: {} } }

    result = Documents::ContextCompression::Service.call(
      question: "pergunta",
      chunks: [],
      query_embedding: [ 0.1 ],
      strategy: strategy
    )

    expect(result.compression_ratio).to eq(0.0)
  end

  it "raises InvalidChunksError when chunks is not an Array" do
    expect do
      Documents::ContextCompression::Service.call(
        question: "pergunta",
        chunks: "não é um array",
        query_embedding: [ 0.1 ],
        strategy: fake_strategy { |_| { chunks: [], scores: {} } }
      )
    end.to raise_error(Documents::ContextCompression::Service::InvalidChunksError)
  end

  it "raises InvalidStrategyError when the strategy does not respond to call" do
    expect do
      Documents::ContextCompression::Service.call(
        question: "pergunta",
        chunks: [],
        query_embedding: [ 0.1 ],
        strategy: Object.new
      )
    end.to raise_error(Documents::ContextCompression::Service::InvalidStrategyError)
  end

  it "wraps an unexpected strategy failure as CompressionError" do
    strategy = fake_strategy { |_kwargs| raise "algo quebrou" }

    expect do
      Documents::ContextCompression::Service.call(
        question: "pergunta",
        chunks: [],
        query_embedding: [ 0.1 ],
        strategy: strategy
      )
    end.to raise_error(Documents::ContextCompression::Service::CompressionError)
  end

  it "wraps a strategy result missing the :chunks key as CompressionError" do
    strategy = fake_strategy { |_kwargs| { scores: {} } }

    expect do
      Documents::ContextCompression::Service.call(
        question: "pergunta",
        chunks: [],
        query_embedding: [ 0.1 ],
        strategy: strategy
      )
    end.to raise_error(Documents::ContextCompression::Service::CompressionError)
  end
end
