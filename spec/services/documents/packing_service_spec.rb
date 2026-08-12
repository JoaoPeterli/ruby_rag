require "rails_helper"

RSpec.describe Documents::PackingService do
  # Conta "tokens" como palavras separadas por espaço em branco, incluindo
  # o separador "\n\n" nessa contagem — assim os números batem sem
  # depender do tiktoken real.
  def word_count_tokenizer
    @word_count_tokenizer ||= Class.new do
      def self.count(text)
        text.to_s.split.size
      end
    end
  end

  it "packs chunks together while the running token count stays within max_tokens" do
    chunks = [ "um dois tres", "quatro cinco seis", "sete oito nove dez" ]

    packed = Documents::PackingService.call(chunks, max_tokens: 6, tokenizer: word_count_tokenizer)

    expect(packed).to eq([ "um dois tres\n\nquatro cinco seis", "sete oito nove dez" ])
  end

  it "starts a new packed chunk once adding the next one would exceed max_tokens" do
    chunks = [ "um dois", "tres quatro", "cinco seis" ]

    packed = Documents::PackingService.call(chunks, max_tokens: 4, tokenizer: word_count_tokenizer)

    expect(packed).to eq([ "um dois\n\ntres quatro", "cinco seis" ])
  end

  it "raises ChunkTooLargeError when a single chunk alone exceeds max_tokens" do
    chunks = [ "um dois tres quatro cinco seis sete" ]

    error = nil
    begin
      Documents::PackingService.call(chunks, max_tokens: 6, tokenizer: word_count_tokenizer)
    rescue Documents::PackingService::ChunkTooLargeError => e
      error = e
    end

    expect(error).to be_a(Documents::PackingService::ChunkTooLargeError)
    expect(error.message).to include("7 tokens")
    expect(error.message).to include("6")
  end

  it "ignores blank chunks" do
    packed = Documents::PackingService.call(
      [ "", "   ", "conteúdo válido" ],
      max_tokens: 10,
      tokenizer: word_count_tokenizer
    )

    expect(packed).to eq([ "conteúdo válido" ])
  end

  it "returns an empty array when every chunk is blank" do
    packed = Documents::PackingService.call([ "", "  " ], max_tokens: 10, tokenizer: word_count_tokenizer)

    expect(packed).to eq([])
  end
end
