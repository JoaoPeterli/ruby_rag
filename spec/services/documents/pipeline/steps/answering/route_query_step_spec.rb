require "rails_helper"

RSpec.describe Documents::Pipeline::Steps::Answering::RouteQueryStep do
  def build_context(config:, result: nil)
    context = Documents::Pipeline::AnswerContext.new(
      question: "Qual o prazo da apólice?",
      account_id: nil,
      conversation_history: [],
      config: config,
      on_delta: nil,
      started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC)
    )
    context.effective_question = "Qual o prazo da apólice?"
    context.result = result
    context
  end

  def unreachable_service
    Class.new { define_singleton_method(:call) { |**_kwargs| raise "não deveria ser chamado" } }
  end

  it "does not call the router when it is disabled" do
    context = build_context(config: base_config(query_router_enabled: false, query_router_service: unreachable_service))

    Documents::Pipeline::Steps::Answering::RouteQueryStep.call(context: context)

    expect(context.route_query).to be_nil
  end

  it "does not call the router when the context already has a result" do
    context = build_context(
      config: base_config(query_router_enabled: true, query_router_service: unreachable_service),
      result: :already_resolved
    )

    Documents::Pipeline::Steps::Answering::RouteQueryStep.call(context: context)

    expect(context.route_query).to be_nil
  end

  it "routes the question and stores the result when enabled" do
    routed = Documents::QueryRouterService::Result.new(category: "factual", reason: "pergunta direta", model: "fake-model", duration_ms: 1.0)
    fake_service = Class.new do
      define_singleton_method(:call) { |**_kwargs| routed }
    end

    context = build_context(config: base_config(query_router_enabled: true, query_router_service: fake_service))

    Documents::Pipeline::Steps::Answering::RouteQueryStep.call(context: context)

    expect(context.route_query).to eq(routed)
  end

  it "clears route_query and swallows the error when the router raises" do
    raising_service = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise Documents::QueryRouterService::Error, "falha" }
    end

    context = build_context(config: base_config(query_router_enabled: true, query_router_service: raising_service))

    Documents::Pipeline::Steps::Answering::RouteQueryStep.call(context: context)

    expect(context.route_query).to be_nil
  end
end
