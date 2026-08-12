require "rails_helper"

RSpec.describe Documents::CrossEncoder::LlmBatchStrategy do
  let(:document) { create(:document) }

  def build_chunk(position:)
    document.document_chunks.create!(
      content: "Conteúdo #{position}.",
      position: position,
      embedding: Array.new(1536, 0.01)
    )
  end

  def build_result(chunk)
    Documents::VectorSearchService::Result.new(chunk: chunk, distance: 0.1, similarity: 0.5, position: 1)
  end

  def fake_chat_service(&responder)
    Class.new do
      define_singleton_method(:call) do |**kwargs|
        content = responder.call(kwargs)

        Ai::ChatCompletionService::Result.new(
          content: content, model: "fake-model", finish_reason: "stop",
          usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 },
          prompt_tokens: 1, completion_tokens: 1, total_tokens: 2, duration_ms: 1.0
        )
      end
    end
  end

  it "raises for a non-positive batch_size" do
    chunk = build_chunk(position: 0)

    expect do
      Documents::CrossEncoder::LlmBatchStrategy.call(
        question: "pergunta",
        results: [ build_result(chunk) ],
        batch_size: 0,
        chat_completion_service: fake_chat_service { "{}" }
      )
    end.to raise_error(Documents::CrossEncoder::LlmBatchStrategy::InvalidBatchSizeError)
  end

  it "clamps an out-of-range score and truncates a long reason" do
    chunk = build_chunk(position: 0)
    long_reason = "x" * 400

    response = fake_chat_service do |_kwargs|
      { scores: [ { chunk_id: chunk.id, score: 1.7, reason: long_reason } ] }.to_json
    end

    evaluations = Documents::CrossEncoder::LlmBatchStrategy.call(
      question: "pergunta",
      results: [ build_result(chunk) ],
      chat_completion_service: response
    ).fetch(:evaluations)

    expect(evaluations.size).to eq(1)
    expect(evaluations.first.score).to be_within(0.0001).of(1.0)
    expect(evaluations.first.reason.length).to eq(240)
  end

  it "defaults to a zero score when the model omits an expected chunk" do
    answered_chunk = build_chunk(position: 0)
    unanswered_chunk = build_chunk(position: 1)

    response = fake_chat_service do |_kwargs|
      { scores: [ { chunk_id: answered_chunk.id, score: 0.9, reason: "motivo" } ] }.to_json
    end

    evaluations = Documents::CrossEncoder::LlmBatchStrategy.call(
      question: "pergunta",
      results: [ build_result(answered_chunk), build_result(unanswered_chunk) ],
      chat_completion_service: response
    ).fetch(:evaluations)

    by_chunk_id = evaluations.index_by(&:chunk_id)
    expect(by_chunk_id[answered_chunk.id].score).to be_within(0.0001).of(0.9)
    expect(by_chunk_id[unanswered_chunk.id].score).to be_within(0.0001).of(0.0)
    expect(by_chunk_id[unanswered_chunk.id].reason).to eq("O modelo não retornou avaliação para este chunk.")
  end

  it "splits work into batches according to batch_size and merges the results" do
    chunks = Array.new(3) { |index| build_chunk(position: index) }
    call_count = 0

    response = fake_chat_service do |_kwargs|
      call_count += 1

      { scores: chunks.map { |chunk| { chunk_id: chunk.id, score: 0.5, reason: "ok" } } }.to_json
    end

    result = Documents::CrossEncoder::LlmBatchStrategy.call(
      question: "pergunta",
      results: chunks.map { |chunk| build_result(chunk) },
      batch_size: 2,
      model: "modelo-configurado",
      chat_completion_service: response
    )

    expect(call_count).to eq(2)
    expect(result.fetch(:evaluations).size).to eq(3)
    expect(result.fetch(:model)).to eq("modelo-configurado")
  end

  it "strips markdown code fences before parsing the JSON" do
    chunk = build_chunk(position: 0)
    fenced = "```json\n#{{ scores: [ { chunk_id: chunk.id, score: 0.6, reason: 'ok' } ] }.to_json}\n```"

    evaluations = Documents::CrossEncoder::LlmBatchStrategy.call(
      question: "pergunta",
      results: [ build_result(chunk) ],
      chat_completion_service: fake_chat_service { fenced }
    ).fetch(:evaluations)

    expect(evaluations.first.score).to be_within(0.0001).of(0.6)
  end

  it "wraps chat completion errors as GenerationError" do
    chunk = build_chunk(position: 0)

    raising_service = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise Ai::ChatCompletionService::Error, "instabilidade" }
    end

    expect do
      Documents::CrossEncoder::LlmBatchStrategy.call(
        question: "pergunta",
        results: [ build_result(chunk) ],
        chat_completion_service: raising_service
      )
    end.to raise_error(Documents::CrossEncoder::LlmBatchStrategy::GenerationError)
  end

  it "raises InvalidResponseError for a malformed JSON response" do
    chunk = build_chunk(position: 0)

    expect do
      Documents::CrossEncoder::LlmBatchStrategy.call(
        question: "pergunta",
        results: [ build_result(chunk) ],
        chat_completion_service: fake_chat_service { "isso não é json" }
      )
    end.to raise_error(Documents::CrossEncoder::LlmBatchStrategy::InvalidResponseError)
  end
end
