require "rails_helper"

RSpec.describe Documents::OverlapService do
  it "returns an empty array for no chunks" do
    expect(Documents::OverlapService.call([])).to eq([])
  end

  it "returns a single chunk untouched" do
    expect(Documents::OverlapService.call([ "único bloco" ])).to eq([ "único bloco" ])
  end

  it "prefixes each subsequent chunk with trailing sentences from the previous one, within the overlap budget" do
    chunks = [ "Frase A. Frase B. Frase C.", "Próximo bloco de texto." ]

    result = Documents::OverlapService.call(chunks, overlap_size: 18)

    expect(result[0]).to eq("Frase A. Frase B. Frase C.")
    expect(result[1]).to eq("Frase B.\n\nFrase C.\n\nPróximo bloco de texto.")
  end

  it "falls back to a hard character cut when no separator fits within the overlap budget" do
    giant_word = "a" * 50

    result = Documents::OverlapService.call([ giant_word, "próximo" ], overlap_size: 10)

    expect(result[1]).to eq("aaaaaaaaaa\n\npróximo")
  end

  it "does not prefix an overlap when the previous chunk is blank" do
    result = Documents::OverlapService.call([ "   ", "conteúdo" ], overlap_size: 20)

    expect(result[1]).to eq("conteúdo")
  end
end
