require "rails_helper"

RSpec.describe Documents::CrossEncoder::Strategy do
  def result_double_class
    @result_double_class ||= Struct.new(:id, :content) do
      def chunk
        self
      end
    end
  end

  it "raises NotImplementedError when called directly" do
    expect do
      Documents::CrossEncoder::Strategy.call(question: "pergunta", results: [])
    end.to raise_error(NotImplementedError)
  end

  it "validate! raises for a blank question" do
    subclass = build_validating_subclass

    expect do
      subclass.call(question: "", results: [ result_double_class.new(1, "conteudo") ])
    end.to raise_error(Documents::CrossEncoder::Strategy::InvalidQuestionError)
  end

  it "validate! raises when a result's chunk lacks the expected shape" do
    subclass = build_validating_subclass
    result_with_nil_chunk = Struct.new(:chunk).new(nil)

    expect do
      subclass.call(question: "pergunta", results: [ result_with_nil_chunk ])
    end.to raise_error(Documents::CrossEncoder::Strategy::InvalidResultsError)
  end

  it "validate! passes for well-formed input" do
    subclass = build_validating_subclass

    expect(subclass.call(question: "pergunta", results: [ result_double_class.new(1, "conteudo") ])).to eq(:ok)
  end

  private

  def build_validating_subclass
    Class.new(Documents::CrossEncoder::Strategy) do
      def call
        validate!
        :ok
      end
    end
  end
end
