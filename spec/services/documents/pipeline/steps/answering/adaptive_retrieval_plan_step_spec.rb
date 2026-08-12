require "rails_helper"

RSpec.describe Documents::Pipeline::Steps::Answering::AdaptiveRetrievalPlanStep do
  def config_double_class
    @config_double_class ||= Struct.new(:adaptive_retrieval_enabled, :adaptive_retrieval_planner, keyword_init: true)
  end

  def route_query_double_class
    @route_query_double_class ||= Struct.new(:category, keyword_init: true)
  end

  def build_context(config:, route_query: nil, result: nil)
    context = Documents::Pipeline::AnswerContext.new(
      question: "Qual o prazo da apólice?",
      account_id: nil,
      conversation_history: [],
      config: config,
      on_delta: nil,
      started_at: 0.0
    )
    context.effective_question = "Qual o prazo da apólice?"
    context.route_query = route_query
    context.result = result
    context
  end

  it "does nothing when context.result is already set, short-circuiting the rest of the pipeline" do
    unreachable_planner = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise "should not be called" }
    end

    context = build_context(
      config: config_double_class.new(adaptive_retrieval_enabled: true, adaptive_retrieval_planner: unreachable_planner),
      result: :cache_hit
    )

    Documents::Pipeline::Steps::Answering::AdaptiveRetrievalPlanStep.call(context: context)

    expect(context.adaptive_plan).to be_nil
  end

  it "does nothing when adaptive retrieval is disabled" do
    unreachable_planner = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise "should not be called" }
    end

    context = build_context(
      config: config_double_class.new(adaptive_retrieval_enabled: false, adaptive_retrieval_planner: unreachable_planner)
    )

    Documents::Pipeline::Steps::Answering::AdaptiveRetrievalPlanStep.call(context: context)

    expect(context.adaptive_plan).to be_nil
  end

  it "sets context.adaptive_plan from the planner, forwarding the effective question and the route category" do
    received = nil
    plan = Documents::AdaptiveRetrievalPlanner::Plan.new(
      query_expansion_enabled: true, multi_query_enabled: false, metadata_extraction_enabled: true,
      cross_encoder_enabled: false, parent_retrieval_enabled: false, context_compression_enabled: false,
      complexity: :simple
    )
    fake_planner = Class.new do
      define_singleton_method(:call) do |**kwargs|
        received = kwargs
        plan
      end
    end

    context = build_context(
      config: config_double_class.new(adaptive_retrieval_enabled: true, adaptive_retrieval_planner: fake_planner),
      route_query: route_query_double_class.new(category: "comparativa")
    )

    Documents::Pipeline::Steps::Answering::AdaptiveRetrievalPlanStep.call(context: context)

    expect(context.adaptive_plan).to eq(plan)
    expect(received).to eq({ question: "Qual o prazo da apólice?", category: "comparativa" })
  end

  it "recovers to a nil adaptive_plan instead of raising when the planner fails" do
    raising_planner = Class.new do
      define_singleton_method(:call) do |**_kwargs|
        raise Documents::AdaptiveRetrievalPlanner::Error, "explodiu"
      end
    end

    context = build_context(
      config: config_double_class.new(adaptive_retrieval_enabled: true, adaptive_retrieval_planner: raising_planner)
    )

    Documents::Pipeline::Steps::Answering::AdaptiveRetrievalPlanStep.call(context: context)

    expect(context.adaptive_plan).to be_nil
  end
end
