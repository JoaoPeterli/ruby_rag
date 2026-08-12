require "rails_helper"

RSpec.describe Documents::Pipeline::AnswerContext do
  it "echoes the constructor arguments and leaves every other slot nil" do
    on_delta = ->(_delta) { }
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    config = Object.new

    context = Documents::Pipeline::AnswerContext.new(
      question: "Qual o prazo da apólice?",
      account_id: 42,
      conversation_history: [ { role: "user", content: "oi" } ],
      config: config,
      on_delta: on_delta,
      started_at: started_at
    )

    expect(context.question).to eq("Qual o prazo da apólice?")
    expect(context.account_id).to eq(42)
    expect(context.conversation_history).to eq([ { role: "user", content: "oi" } ])
    expect(context.config).to equal(config)
    expect(context.on_delta).to equal(on_delta)
    expect(context.started_at).to eq(started_at)

    %i[
      normalized_question effective_question query_rewrite_result
      question_embedding cache_hit route_query adaptive_plan token_budget
      retrieval_result context_result prompt chat_result citation_result
      groundedness_result hallucination_result confidence_result result
    ].each do |attribute|
      expect(context.public_send(attribute)).to be_nil, "expected #{attribute} to start nil"
    end
  end

  it "keeps every attribute mutable, which is how pipeline steps thread state through" do
    context = Documents::Pipeline::AnswerContext.new(
      question: "pergunta",
      account_id: nil,
      conversation_history: [],
      config: Object.new,
      on_delta: nil,
      started_at: 0.0
    )

    context.effective_question = "pergunta reescrita"
    context.cache_hit = true
    context.result = :cache_short_circuit

    expect(context.effective_question).to eq("pergunta reescrita")
    expect(context.cache_hit).to be_truthy
    expect(context.result).to eq(:cache_short_circuit)
  end
end
