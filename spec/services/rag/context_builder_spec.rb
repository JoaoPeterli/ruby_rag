require "rails_helper"

RSpec.describe Rag::ContextBuilder do
  def chunk_double_class
    @chunk_double_class ||= Struct.new(:content)
  end

  it "numbers each chunk and joins them with a separator" do
    context = Rag::ContextBuilder.call([ chunk_double_class.new("Primeiro texto."), chunk_double_class.new("Segundo texto.") ])

    expect(context).to match("Documento 1")
    expect(context).to match("Primeiro texto.")
    expect(context).to match("Documento 2")
    expect(context).to match("Segundo texto.")
    expect(context.index("Documento 1")).to be < context.index("Documento 2")
  end

  it "returns an empty string for no chunks" do
    expect(Rag::ContextBuilder.call([])).to eq("")
  end
end
