require "rails_helper"

RSpec.describe Ai::TokenizedText do
  it "matches the real tokenizer count for the stripped text" do
    tokenized = Ai::TokenizedText.new("  A apólice cobre roubo.  ")

    expect(tokenized.text).to eq("A apólice cobre roubo.")
    expect(tokenized.size).to eq(Ai::Tokenizer.count("A apólice cobre roubo."))
  end

  it "has zero tokens for an empty text" do
    tokenized = Ai::TokenizedText.new("   ")

    expect(tokenized.text).to eq("")
    expect(tokenized.size).to eq(0)
  end

  it "coerces a non-string value to string before tokenizing" do
    tokenized = Ai::TokenizedText.new(42)

    expect(tokenized.text).to eq("42")
    expect(tokenized.size).to eq(Ai::Tokenizer.count("42"))
  end
end
