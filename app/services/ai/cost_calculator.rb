# frozen_string_literal: true

module Ai
  class CostCalculator
    Result = Data.define(
      :model,
      :prompt_tokens,
      :completion_tokens,
      :total_tokens,
      :prompt_cost_usd,
      :completion_cost_usd,
      :total_cost_usd,
      :priced
    )

    def self.call(...)
      new(...).call
    end

    def initialize(
      model:,
      prompt_tokens:,
      completion_tokens:
    )
      @model = model.to_s
      @prompt_tokens = prompt_tokens.to_i
      @completion_tokens = completion_tokens.to_i
    end

    def call
      rate = pricing_for(model)

      prompt_cost = (prompt_tokens / 1_000_000.0) * rate.fetch(:input)
      completion_cost = (completion_tokens / 1_000_000.0) * rate.fetch(:output)

      Result.new(
        model: model,
        prompt_tokens: prompt_tokens,
        completion_tokens: completion_tokens,
        total_tokens: prompt_tokens + completion_tokens,
        prompt_cost_usd: prompt_cost.round(6),
        completion_cost_usd: completion_cost.round(6),
        total_cost_usd: (prompt_cost + completion_cost).round(6),
        priced: rate.fetch(:configured)
      )
    end

    private

    attr_reader :model, :prompt_tokens, :completion_tokens

    # Preços não são embutidos no código: variam por modelo e mudam com o
    # tempo. Configure via ENV (USD por 1M tokens) para que o custo seja
    # real; sem configuração, retorna 0 com priced: false.
    def pricing_for(model)
      env_key = model.upcase.gsub(/[^A-Z0-9]/, "_")

      input = ENV["OPENAI_PRICE_#{env_key}_INPUT_PER_1M"]
      output = ENV["OPENAI_PRICE_#{env_key}_OUTPUT_PER_1M"]

      {
        input: input.to_f,
        output: output.to_f,
        configured: input.present? && output.present?
      }
    end
  end
end
