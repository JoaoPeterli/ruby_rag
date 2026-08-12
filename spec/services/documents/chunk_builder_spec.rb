require "rails_helper"

RSpec.describe Documents::ChunkBuilder do
  def fake_tokenizer
    Class.new do
      # Deterministic stand-in: token count == number of words.
      define_singleton_method(:count) { |text| text.to_s.split.size }
    end
  end

  it "adds text while under the token budget and joins with the separator" do
    builder = Documents::ChunkBuilder.new(max_tokens: 10, tokenizer: fake_tokenizer)

    expect(builder.add("um dois tres")).to be_truthy
    expect(builder.add("quatro cinco")).to be_truthy

    expect(builder.text).to eq("um dois tres\n\nquatro cinco")
    expect(builder.token_count).to eq(5)
  end

  it "rejects text that would push the chunk over max_tokens, without mutating state" do
    builder = Documents::ChunkBuilder.new(max_tokens: 3, tokenizer: fake_tokenizer)

    expect(builder.add("um dois tres")).to be_truthy
    expect(builder.add("mais um texto grande")).to be_falsey

    expect(builder.text).to eq("um dois tres")
    expect(builder.token_count).to eq(3)
  end

  it "fits? previews whether text would fit without mutating the builder" do
    builder = Documents::ChunkBuilder.new(max_tokens: 3, tokenizer: fake_tokenizer)

    expect(builder.fits?("um dois tres")).to be_truthy
    expect(builder.fits?("um dois tres quatro")).to be_falsey
    expect(builder.empty?).to be_truthy
  end

  it "empty? and present? reflect whether any text was accepted" do
    builder = Documents::ChunkBuilder.new(max_tokens: 10, tokenizer: fake_tokenizer)

    expect(builder.empty?).to be_truthy
    expect(builder.present?).to be_falsey

    builder.add("algum texto")

    expect(builder.empty?).to be_falsey
    expect(builder.present?).to be_truthy
  end

  it "reset clears accumulated text and token_count and returns self" do
    builder = Documents::ChunkBuilder.new(max_tokens: 10, tokenizer: fake_tokenizer)
    builder.add("algum texto")

    result = builder.reset

    expect(result).to equal(builder)
    expect(builder.empty?).to be_truthy
    expect(builder.token_count).to eq(0)
  end

  it "ignores blank text without raising" do
    builder = Documents::ChunkBuilder.new(max_tokens: 10, tokenizer: fake_tokenizer)

    expect(builder.add("   ")).to be_falsey
    expect(builder.empty?).to be_truthy
  end

  it "uses the real Ai::Tokenizer by default" do
    builder = Documents::ChunkBuilder.new(max_tokens: 50)

    expect(builder.add("A apólice cobre roubo e incêndio.")).to be_truthy
    expect(builder.token_count).to eq(Ai::Tokenizer.count("A apólice cobre roubo e incêndio."))
  end
end
