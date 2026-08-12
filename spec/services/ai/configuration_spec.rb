require "rails_helper"

RSpec.describe Ai::Configuration do
  it "exposes the configured chat and embedding models" do
    expect(Ai::Configuration.chat_model).to eq("gpt-4.1-mini")
    expect(Ai::Configuration.embedding_model).to eq("text-embedding-3-small")
  end

  it "aliases open_timeout and read_timeout to the HTTP timeout constants" do
    expect(Ai::Configuration.open_timeout).to eq(Ai::Configuration::HTTP_OPEN_TIMEOUT)
    expect(Ai::Configuration.read_timeout).to eq(Ai::Configuration::HTTP_READ_TIMEOUT)
  end

  it "passes validate! with the current (well-formed) test configuration" do
    expect(Ai::Configuration.validate!).to be(true)
  end

  it "raises on validate! when the API key is blank" do
    with_env("OPENAI_API_KEY" => "") do
      expect { Ai::Configuration.validate! }.to raise_error(Ai::Configuration::ConfigurationError)
    end
  end

  it "raises on validate! when the chat temperature is out of range" do
    allow(Ai::Configuration).to receive(:chat_temperature).and_return(5.0)

    expect { Ai::Configuration.validate! }.to raise_error(Ai::Configuration::ConfigurationError)
  end

  it "raises on validate! when a URL is not absolute HTTP(S)" do
    allow(Ai::Configuration).to receive(:base_url).and_return("not-a-url")

    expect { Ai::Configuration.validate! }.to raise_error(Ai::Configuration::ConfigurationError)
  end

  def with_env(overrides)
    originals = overrides.keys.index_with { |key| ENV[key] }

    overrides.each { |key, value| ENV[key] = value }

    yield
  ensure
    originals.each { |key, value| ENV[key] = value }
  end
end
