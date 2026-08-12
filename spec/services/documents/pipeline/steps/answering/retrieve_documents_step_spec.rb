require "rails_helper"

RSpec.describe Documents::Pipeline::Steps::Answering::RetrieveDocumentsStep do
  def plan_double_class
    @plan_double_class ||= Struct.new(
      :query_expansion_enabled, :multi_query_enabled, :metadata_extraction_enabled,
      :cross_encoder_enabled, :parent_retrieval_enabled, :context_compression_enabled,
      keyword_init: true
    )
  end

  def build_context(config:, result: nil, adaptive_plan: nil, account_id: 7)
    context = Documents::Pipeline::AnswerContext.new(
      question: "Qual o prazo da apólice?",
      account_id: account_id,
      conversation_history: [],
      config: config,
      on_delta: nil,
      started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC)
    )
    context.effective_question = "Qual o prazo da apólice?"
    context.result = result
    context.adaptive_plan = adaptive_plan
    context
  end

  def unreachable_pipeline
    Class.new { define_singleton_method(:call) { |**_kwargs| raise "não deveria ser chamado" } }
  end

  it "does nothing when the context already has a result" do
    context = build_context(config: base_config(retrieval_pipeline: unreachable_pipeline), result: :already_resolved)

    Documents::Pipeline::Steps::Answering::RetrieveDocumentsStep.call(context: context)

    expect(context.retrieval_result).to be_nil
  end

  it "calls the retrieval pipeline with the effective question and configured limits" do
    received = nil
    sentinel = Object.new
    fake_pipeline = Class.new do
      define_singleton_method(:call) { |**kwargs| received = kwargs; sentinel }
    end

    context = build_context(
      config: base_config(
        retrieval_pipeline: fake_pipeline,
        search_limit: 5, candidate_limit: 20, minimum_similarity: 0.30, mmr_lambda: 0.70
      )
    )

    Documents::Pipeline::Steps::Answering::RetrieveDocumentsStep.call(context: context)

    expect(context.retrieval_result).to eq(sentinel)
    expect(received[:question]).to eq("Qual o prazo da apólice?")
    expect(received[:account_id]).to eq(7)
    expect(received[:search_limit]).to eq(5)
    expect(received[:candidate_limit]).to eq(20)
    expect(received[:minimum_similarity]).to be_within(0.0001).of(0.30)
    expect(received[:mmr_lambda]).to be_within(0.0001).of(0.70)
  end

  it "lets an explicit config flag override the adaptive plan" do
    received = nil
    fake_pipeline = Class.new { define_singleton_method(:call) { |**kwargs| received = kwargs; nil } }

    context = build_context(
      config: base_config(retrieval_pipeline: fake_pipeline, cross_encoder_enabled: false),
      adaptive_plan: plan_double_class.new(cross_encoder_enabled: true)
    )

    Documents::Pipeline::Steps::Answering::RetrieveDocumentsStep.call(context: context)

    expect(received[:cross_encoder_enabled]).to eq(false)
  end

  it "falls back to the adaptive plan when the config leaves the flag unset" do
    received = nil
    fake_pipeline = Class.new { define_singleton_method(:call) { |**kwargs| received = kwargs; nil } }

    context = build_context(
      config: base_config(retrieval_pipeline: fake_pipeline, cross_encoder_enabled: nil),
      adaptive_plan: plan_double_class.new(cross_encoder_enabled: true)
    )

    Documents::Pipeline::Steps::Answering::RetrieveDocumentsStep.call(context: context)

    expect(received[:cross_encoder_enabled]).to eq(true)
  end

  it "omits the flag entirely when neither the config nor the plan set it" do
    received = nil
    fake_pipeline = Class.new { define_singleton_method(:call) { |**kwargs| received = kwargs; nil } }

    context = build_context(
      config: base_config(retrieval_pipeline: fake_pipeline, cross_encoder_enabled: nil),
      adaptive_plan: nil
    )

    Documents::Pipeline::Steps::Answering::RetrieveDocumentsStep.call(context: context)

    expect(received.key?(:cross_encoder_enabled)).to be_falsey
  end

  it "sets a no-evidence result when the pipeline finds nothing relevant" do
    raising_pipeline = Class.new do
      define_singleton_method(:call) do |**_kwargs|
        raise Documents::RetrievalPipelineService::NoRelevantResultsError.new(
          "Nenhum conteúdo relevante foi encontrado",
          search_query: "pergunta reescrita",
          queries: [ "pergunta reescrita" ],
          metrics: {},
          stage_failures: [],
          duration_ms: 12.0
        )
      end
    end

    context = build_context(config: base_config(retrieval_pipeline: raising_pipeline))
    context.normalized_question = "Qual o prazo da apólice?"

    Documents::Pipeline::Steps::Answering::RetrieveDocumentsStep.call(context: context)

    expect(context.result.refused).to be_truthy
    expect(context.result.answer).to eq(Documents::QuestionAnsweringService::NO_EVIDENCE_ANSWER)
    expect(context.result.search_query).to eq("pergunta reescrita")
  end

  it "wraps a generic pipeline failure as a RetrievalError" do
    raising_pipeline = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise Documents::RetrievalPipelineService::Error, "erro interno" }
    end

    context = build_context(config: base_config(retrieval_pipeline: raising_pipeline))

    expect do
      Documents::Pipeline::Steps::Answering::RetrieveDocumentsStep.call(context: context)
    end.to raise_error(Documents::QuestionAnsweringService::RetrievalError, /erro interno/)
  end
end
