require "rails_helper"

RSpec.describe Documents::Pipeline::Steps::Answering::TokenBudgetStep do
  def build_context(config:, result: nil)
    context = Documents::Pipeline::AnswerContext.new(
      question: "Qual o prazo da apólice?",
      account_id: nil,
      conversation_history: [],
      config: config,
      on_delta: nil,
      started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC)
    )
    context.result = result
    context
  end

  def unreachable_service
    Class.new { define_singleton_method(:call) { |**_kwargs| raise "não deveria ser chamado" } }
  end

  it "does nothing when the context already has a result" do
    context = build_context(
      config: base_config(token_budget_enabled: true, token_budget_service: unreachable_service),
      result: :already_resolved
    )

    Documents::Pipeline::Steps::Answering::TokenBudgetStep.call(context: context)

    expect(context.token_budget).to be_nil
  end

  it "does nothing when token budgeting is disabled" do
    context = build_context(config: base_config(token_budget_enabled: false, token_budget_service: unreachable_service))

    Documents::Pipeline::Steps::Answering::TokenBudgetStep.call(context: context)

    expect(context.token_budget).to be_nil
  end

  it "computes and stores the budget using the configured reserves" do
    received = nil
    budget_result = Documents::TokenBudgetService::Result.new(
      total_budget_tokens: 8000, response_budget_tokens: 800,
      system_prompt_reserve_tokens: 300, context_budget_tokens: 6900,
      context_budget_characters: 27600
    )
    fake_service = Class.new do
      define_singleton_method(:call) { |**kwargs| received = kwargs; budget_result }
    end

    context = build_context(
      config: base_config(
        token_budget_enabled: true, token_budget_total: 8000,
        token_budget_response_reserve: 800, token_budget_system_prompt_reserve: 300,
        token_budget_service: fake_service
      )
    )

    Documents::Pipeline::Steps::Answering::TokenBudgetStep.call(context: context)

    expect(context.token_budget).to eq(budget_result)
    expect(received[:total_budget]).to eq(8000)
    expect(received[:response_reserve]).to eq(800)
    expect(received[:system_prompt_reserve]).to eq(300)
  end

  it "clears token_budget when the service raises" do
    raising_service = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise Documents::TokenBudgetService::Error, "falha" }
    end

    context = build_context(config: base_config(token_budget_enabled: true, token_budget_service: raising_service))

    Documents::Pipeline::Steps::Answering::TokenBudgetStep.call(context: context)

    expect(context.token_budget).to be_nil
  end
end
