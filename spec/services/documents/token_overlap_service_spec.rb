require "rails_helper"

RSpec.describe Documents::TokenOverlapService do
  it "returns one chunk without overlap for the very first chunk" do
    result = Documents::TokenOverlapService.call([ "Primeiro parágrafo sobre averbação." ])

    expect(result.size).to eq(1)
    expect(result.first.content).to eq("Primeiro parágrafo sobre averbação.")
    expect(result.first.overlap?).to be_falsey
  end

  it "builds overlap from the tail of the previous chunk for subsequent chunks" do
    result = Documents::TokenOverlapService.call(
      [ "Primeiro parágrafo sobre averbação.", "Segundo parágrafo sobre apólices." ],
      overlap_tokens: 5
    )

    expect(result.size).to eq(2)
    expect(result.first.overlap?).to be_falsey
    expect(result.last.overlap?).to be_truthy
    expect(result.last.content).to eq("Segundo parágrafo sobre apólices.")
    expect(result.last.text.start_with?(result.last.overlap)).to be_truthy
    expect(result.last.text.end_with?(result.last.content)).to be_truthy
  end

  it "falls back to token-level splitting when the previous chunk has no natural separators" do
    huge_word = "a" * 3000

    result = Documents::TokenOverlapService.call([ huge_word, "Próximo parágrafo." ], overlap_tokens: 5)

    overlap = result.last.overlap
    expect(overlap).to be_present
    expect(overlap.length).to be < huge_word.length
  end

  it "drops blank chunks before processing" do
    result = Documents::TokenOverlapService.call([ "  ", "Conteúdo válido.", "" ])

    expect(result.size).to eq(1)
    expect(result.first.content).to eq("Conteúdo válido.")
  end

  it "returns an empty array when every chunk is blank" do
    expect(Documents::TokenOverlapService.call([ "", "   ", nil ])).to be_empty
  end
end
