require "rails_helper"

RSpec.describe Documents::ContextCompression::Strategy do
  def chunk_double_class
    @chunk_double_class ||= Struct.new(:id, :content, :embedding, keyword_init: true)
  end

  it "raises NotImplementedError when called directly" do
    expect do
      Documents::ContextCompression::Strategy.call(
        question: "pergunta",
        chunks: [],
        query_embedding: [ 0.1 ]
      )
    end.to raise_error(NotImplementedError)
  end

  it "validate! raises for a blank question" do
    subclass = build_validating_subclass
    chunk = chunk_double_class.new(id: 1, content: "texto", embedding: [ 0.1 ])

    expect do
      subclass.call(question: "   ", chunks: [ chunk ], query_embedding: [ 0.1 ])
    end.to raise_error(Documents::ContextCompression::Strategy::InvalidQuestionError)
  end

  it "validate! raises when chunks do not look like DocumentChunks" do
    subclass = build_validating_subclass

    expect do
      subclass.call(question: "pergunta", chunks: [ { content: "x" } ], query_embedding: [ 0.1 ])
    end.to raise_error(Documents::ContextCompression::Strategy::InvalidChunksError)
  end

  it "validate! raises for an empty query embedding" do
    subclass = build_validating_subclass
    chunk = chunk_double_class.new(id: 1, content: "texto", embedding: [ 0.1 ])

    expect do
      subclass.call(question: "pergunta", chunks: [ chunk ], query_embedding: [])
    end.to raise_error(Documents::ContextCompression::Strategy::InvalidEmbeddingError)
  end

  it "validate! passes for well-formed input" do
    subclass = build_validating_subclass
    chunk = chunk_double_class.new(id: 1, content: "texto", embedding: [ 0.1 ])

    expect(subclass.call(question: "pergunta", chunks: [ chunk ], query_embedding: [ 0.1 ])).to eq(:ok)
  end

  private

  def build_validating_subclass
    Class.new(Documents::ContextCompression::Strategy) do
      def call
        validate!
        :ok
      end
    end
  end
end
