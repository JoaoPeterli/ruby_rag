require "rails_helper"

RSpec.describe Documents::ContextBuilder do
  def build_result(chunk_id:, document_id:, content:, position:, score: 0.9, distance: 0.1)
    Documents::VectorSearchResult.new(
      chunk_id: chunk_id,
      document_id: document_id,
      content: content,
      position: position,
      distance: distance,
      score: score,
      metadata: {}
    )
  end

  it "builds a labeled context with one [FONTE n] section per unique chunk" do
    results = [
      build_result(chunk_id: 1, document_id: 1, content: "O prazo é de doze meses.", position: 0)
    ]

    result = Documents::ContextBuilder.call(results: results)

    expect(result.context).to include("[FONTE 1]")
    expect(result.context).to include("O prazo é de doze meses.")
    expect(result.chunks_count).to eq(1)
    expect(result.sources.first[:source_number]).to eq(1)
    expect(result.truncated).to be_falsey
  end

  it "orders chunks by document_id and then by position" do
    results = [
      build_result(chunk_id: 2, document_id: 1, content: "Segundo trecho do documento um.", position: 1),
      build_result(chunk_id: 3, document_id: 2, content: "Único trecho do documento dois.", position: 0),
      build_result(chunk_id: 1, document_id: 1, content: "Primeiro trecho do documento um.", position: 0)
    ]

    result = Documents::ContextBuilder.call(results: results)

    expect(result.sources.map { |source| source[:chunk_id] }).to eq([ 1, 2, 3 ])
  end

  it "deduplicates results whose content is identical once normalized" do
    results = [
      build_result(chunk_id: 1, document_id: 1, content: "Mesmo   conteúdo.", position: 0),
      build_result(chunk_id: 2, document_id: 1, content: "mesmo conteúdo.", position: 1)
    ]

    result = Documents::ContextBuilder.call(results: results)

    expect(result.chunks_count).to eq(1)
    expect(result.input_chunks_count).to eq(2)
    expect(result.discarded_chunks_count).to eq(1)
  end

  it "removes a repeated prefix/suffix overlap between consecutive chunks of the same document" do
    shared = "trecho compartilhado entre os dois pedaços consecutivos aqui"
    results = [
      build_result(chunk_id: 1, document_id: 1, content: "início único. #{shared}", position: 0),
      build_result(chunk_id: 2, document_id: 1, content: "#{shared} fim único.", position: 1)
    ]

    result = Documents::ContextBuilder.call(results: results)

    expect(result.context.scan(shared).count).to eq(1)
  end

  it "truncates the context once max_characters is exceeded and flags truncated" do
    results = [
      build_result(chunk_id: 1, document_id: 1, content: "a" * 50, position: 0),
      build_result(chunk_id: 2, document_id: 1, content: "b" * 500, position: 1)
    ]

    result = Documents::ContextBuilder.call(results: results, max_characters: 200)

    expect(result.truncated).to be_truthy
    expect(result.characters_count).to be <= 200
  end

  it "raises for a result that is not a VectorSearchResult" do
    expect do
      Documents::ContextBuilder.call(results: [ { content: "x" } ])
    end.to raise_error(Documents::ContextBuilder::InvalidResultsError)
  end

  it "raises for a non-positive max_characters" do
    expect do
      Documents::ContextBuilder.call(
        results: [ build_result(chunk_id: 1, document_id: 1, content: "x", position: 0) ],
        max_characters: 0
      )
    end.to raise_error(Documents::ContextBuilder::InvalidMaxCharactersError)
  end
end
