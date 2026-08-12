require "rails_helper"

RSpec.describe Ai::Tokenizer do
  it "counts more tokens for longer text" do
    short = Ai::Tokenizer.count("Olá")
    long = Ai::Tokenizer.count("Olá, este é um texto bem mais longo sobre apólices de seguro.")

    expect(short).to be_positive
    expect(long).to be > short
  end

  it "encode returns an array of integers whose length matches count" do
    tokens = Ai::Tokenizer.encode("prazo de vigência")

    expect(tokens).to be_a(Array)
    expect(tokens).to all(be_a(Integer))
    expect(tokens.length).to eq(Ai::Tokenizer.count("prazo de vigência"))
  end

  it "decode is the inverse of encode" do
    text = "A apólice cobre roubo e incêndio."

    decoded = Ai::Tokenizer.decode(Ai::Tokenizer.encode(text))

    expect(decoded).to eq(text)
  end

  it "treats a non-string value as its string representation" do
    expect(Ai::Tokenizer.count(123)).to eq(Ai::Tokenizer.count("123"))
  end

  it "raises a Tokenizer::Error when encoding with an unknown model (no encoder was resolved)" do
    tokenizer = Ai::Tokenizer.new(model: "modelo-que-nao-existe")

    expect { tokenizer.encode("texto qualquer") }.to raise_error(Ai::Tokenizer::Error)
  end
end
