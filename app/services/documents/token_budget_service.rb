# frozen_string_literal: true

module Documents
  class TokenBudgetService
    DEFAULT_TOTAL_BUDGET = 8_000
    DEFAULT_RESPONSE_RESERVE = 800
    DEFAULT_SYSTEM_PROMPT_RESERVE = 300
    MINIMUM_CONTEXT_BUDGET = 500

    Result = Data.define(
      :total_budget_tokens,
      :response_budget_tokens,
      :system_prompt_reserve_tokens,
      :context_budget_tokens,
      :context_budget_characters
    )

    class Error < StandardError; end
    class InvalidBudgetError < Error; end

    def self.call(...)
      new(...).call
    end

    def initialize(
      total_budget: DEFAULT_TOTAL_BUDGET,
      response_reserve: DEFAULT_RESPONSE_RESERVE,
      system_prompt_reserve: DEFAULT_SYSTEM_PROMPT_RESERVE,
      token_estimator: Ai::TokenEstimator
    )
      @total_budget = total_budget
      @response_reserve = response_reserve
      @system_prompt_reserve = system_prompt_reserve
      @token_estimator = token_estimator
    end

    def call
      validate!

      context_budget_tokens =
        [
          total_budget - response_reserve - system_prompt_reserve,
          MINIMUM_CONTEXT_BUDGET
        ].max

      Result.new(
        total_budget_tokens: total_budget,
        response_budget_tokens: response_reserve,
        system_prompt_reserve_tokens: system_prompt_reserve,
        context_budget_tokens: context_budget_tokens,
        context_budget_characters:
          token_estimator.characters_for(context_budget_tokens)
      )
    end

    private

    attr_reader(
      :total_budget,
      :response_reserve,
      :system_prompt_reserve,
      :token_estimator
    )

    def validate!
      unless total_budget.is_a?(Integer) && total_budget.positive?
        raise InvalidBudgetError, "total_budget deve ser um inteiro maior que zero"
      end

      unless response_reserve.is_a?(Integer) && response_reserve.positive?
        raise InvalidBudgetError, "response_reserve deve ser um inteiro maior que zero"
      end

      return if system_prompt_reserve.is_a?(Integer) && system_prompt_reserve >= 0

      raise InvalidBudgetError,
            "system_prompt_reserve deve ser um inteiro maior ou igual a zero"
    end
  end
end
