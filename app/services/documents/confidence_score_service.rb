# frozen_string_literal: true

module Documents
  class ConfidenceScoreService
    DEFAULT_WEIGHTS = {
      retrieval: 0.25,
      cross_encoder: 0.20,
      citation_coverage: 0.25,
      groundedness: 0.15,
      faithfulness: 0.15
    }.freeze

    LEVEL_THRESHOLDS = {
      high: 0.75,
      medium: 0.45
    }.freeze

    Result = Data.define(
      :score,
      :level,
      :components
    )

    class Error < StandardError; end
    class InvalidComponentsError < Error; end

    def self.call(...)
      new(...).call
    end

    def initialize(
      retrieval_result:,
      citation_result: nil,
      groundedness_result: nil,
      hallucination_result: nil,
      weights: DEFAULT_WEIGHTS
    )
      @retrieval_result = retrieval_result
      @citation_result = citation_result
      @groundedness_result = groundedness_result
      @hallucination_result = hallucination_result
      @weights = weights
    end

    def call
      components = build_components

      if components.empty?
        raise InvalidComponentsError,
              "Nenhum sinal disponível para calcular a confiança"
      end

      score = weighted_average(components)

      Result.new(
        score: score,
        level: level_for(score),
        components: components
      )
    end

    private

    attr_reader(
      :retrieval_result,
      :citation_result,
      :groundedness_result,
      :hallucination_result,
      :weights
    )

    def build_components
      {
        retrieval: retrieval_score_component,
        cross_encoder: cross_encoder_component,
        citation_coverage: citation_coverage_component,
        groundedness: groundedness_component,
        faithfulness: faithfulness_component
      }.compact
    end

    def retrieval_score_component
      results = retrieval_result&.results
      return if results.blank?

      values = results.filter_map { |result| relevance_value(result) }
      return if values.empty?

      (values.sum.to_f / values.size).clamp(0.0, 1.0)
    end

    def relevance_value(result)
      if result.respond_to?(:combined_score) && result.combined_score
        result.combined_score
      elsif result.respond_to?(:rerank_score)
        result.rerank_score
      end
    end

    def cross_encoder_component
      retrieval_result&.cross_encoder&.average_score
    end

    def citation_coverage_component
      citation_result&.citation_coverage
    end

    def groundedness_component
      return unless groundedness_result

      if groundedness_result.refused
        0.5
      elsif groundedness_result.grounded
        1.0
      else
        0.0
      end
    end

    def faithfulness_component
      return unless hallucination_result

      (1.0 - hallucination_result.hallucination_rate).clamp(0.0, 1.0)
    end

    def weighted_average(components)
      total_weight = components.sum { |key, _value| weights.fetch(key, 0.0) }

      return 0.0 if total_weight.zero?

      weighted_sum =
        components.sum { |key, value| value * weights.fetch(key, 0.0) }

      (weighted_sum / total_weight).round(4)
    end

    def level_for(score)
      return :high if score >= LEVEL_THRESHOLDS.fetch(:high)
      return :medium if score >= LEVEL_THRESHOLDS.fetch(:medium)

      :low
    end
  end
end
