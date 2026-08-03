# frozen_string_literal: true

module Documents
  module CrossEncoder
    class Service
      DEFAULT_STRATEGY =
        Documents::CrossEncoder::LlmBatchStrategy

      DEFAULT_CANDIDATE_LIMIT = 20
      DEFAULT_RERANK_LIMIT = 10
      DEFAULT_MINIMUM_SCORE = 0.35
      DEFAULT_CROSS_ENCODER_WEIGHT = 0.75
      DEFAULT_RETRIEVAL_WEIGHT = 0.25

      class Error < StandardError; end
      class InvalidResultsError < Error; end
      class InvalidConfigurationError < Error; end
      class RerankError < Error; end

      def self.call(...)
        new(...).call
      end

      def initialize(
        question:,
        results:,
        candidate_limit: DEFAULT_CANDIDATE_LIMIT,
        rerank_limit: DEFAULT_RERANK_LIMIT,
        minimum_score: DEFAULT_MINIMUM_SCORE,
        cross_encoder_weight:
          DEFAULT_CROSS_ENCODER_WEIGHT,
        retrieval_weight:
          DEFAULT_RETRIEVAL_WEIGHT,
        strategy: DEFAULT_STRATEGY,
        strategy_options: {}
      )
        @question = question
        @results = results
        @candidate_limit = candidate_limit
        @rerank_limit = rerank_limit
        @minimum_score = minimum_score
        @cross_encoder_weight =
          cross_encoder_weight
        @retrieval_weight =
          retrieval_weight
        @strategy = strategy
        @strategy_options = strategy_options
      end

      def call
        started_at = monotonic_time

        validate!

        candidates =
          results.first(candidate_limit)

        strategy_result =
          strategy.call(
            question: question,
            results: candidates,
            **strategy_options
          )

        evaluations =
          strategy_result.fetch(:evaluations)

        scored_results =
          build_scored_results(
            candidates: candidates,
            evaluations: evaluations
          )

        selected_results =
          select_results(scored_results)

        Result.new(
          results: selected_results,
          scores: build_scores(scored_results),
          original_count: results.size,
          evaluated_count: candidates.size,
          reranked_count: selected_results.size,
          average_score:
            average_cross_encoder_score(
              scored_results
            ),
          duration_ms: elapsed_ms(started_at),
          model: strategy_result[:model],
          strategy: strategy.name
        )
      rescue Error
        raise
      rescue Documents::CrossEncoder::Strategy::Error => error
        raise RerankError,
              "A estratégia falhou: #{error.message}"
      rescue KeyError => error
        raise RerankError,
              "Resultado inválido da estratégia: #{error.message}"
      rescue StandardError => error
        raise RerankError,
              "Falha inesperada no re-ranking: #{error.message}"
      end

      private

      attr_reader(
        :question,
        :results,
        :candidate_limit,
        :rerank_limit,
        :minimum_score,
        :cross_encoder_weight,
        :retrieval_weight,
        :strategy,
        :strategy_options
      )

      def validate!
        validate_results!
        validate_limits!
        validate_scores!
        validate_weights!
      end

      def validate_results!
        valid =
          results.is_a?(Array) &&
          results.all? do |result|
            result.respond_to?(:chunk)
          end

        return if valid

        raise InvalidResultsError,
              "results deve ser um array de resultados"
      end

      def validate_limits!
        valid =
          candidate_limit.is_a?(Integer) &&
          candidate_limit.positive? &&
          rerank_limit.is_a?(Integer) &&
          rerank_limit.positive?

        return if valid

        raise InvalidConfigurationError,
              "candidate_limit e rerank_limit devem ser positivos"
      end

      def validate_scores!
        return if minimum_score.is_a?(Numeric) &&
                  minimum_score.between?(0.0, 1.0)

        raise InvalidConfigurationError,
              "minimum_score deve estar entre 0 e 1"
      end

      def validate_weights!
        valid =
          cross_encoder_weight.is_a?(Numeric) &&
          retrieval_weight.is_a?(Numeric) &&
          cross_encoder_weight >= 0 &&
          retrieval_weight >= 0 &&
          (
            cross_encoder_weight +
            retrieval_weight
          ).positive?

        return if valid

        raise InvalidConfigurationError,
              "Os pesos devem ser números não negativos"
      end

      def build_scored_results(
        candidates:,
        evaluations:
      )
        evaluations_by_chunk_id =
          evaluations.index_by(&:chunk_id)

        retrieval_scores =
          candidates.map do |result|
            retrieval_score_for(result)
          end

        normalized_scores =
          normalize_scores(retrieval_scores)

        candidates.each_with_index.map do |result, index|
          evaluation =
            evaluations_by_chunk_id[
              result.chunk.id
            ]

          cross_encoder_score =
            evaluation&.score || 0.0

          retrieval_score =
            normalized_scores[index]

          combined_score =
            calculate_combined_score(
              cross_encoder_score:
                cross_encoder_score,
              retrieval_score:
                retrieval_score
            )

          ScoredResult.new(
            result: result,
            cross_encoder_score:
              cross_encoder_score,
            cross_encoder_reason:
              evaluation&.reason ||
                "Sem avaliação.",
            retrieval_score:
              retrieval_score,
            combined_score:
              combined_score
          )
        end
      end

      def retrieval_score_for(result)
        value =
          attribute_value(
            result,
            :rerank_score
          ) ||
          attribute_value(
            result,
            :multi_query_score
          ) ||
          attribute_value(
            result,
            :hybrid_score
          ) ||
          attribute_value(
            result,
            :similarity
          ) ||
          0.0

        value.to_f
      end

      def attribute_value(result, name)
        return unless result.respond_to?(name)

        result.public_send(name)
      end

      def normalize_scores(scores)
        return [] if scores.empty?

        minimum = scores.min
        maximum = scores.max
        range = maximum - minimum

        return Array.new(scores.size, 1.0) if range.zero?

        scores.map do |score|
          (score - minimum) / range
        end
      end

      def calculate_combined_score(
        cross_encoder_score:,
        retrieval_score:
      )
        total_weight =
          cross_encoder_weight +
          retrieval_weight

        value =
          (
            cross_encoder_score *
              cross_encoder_weight
          ) +
          (
            retrieval_score *
              retrieval_weight
          )

        (value / total_weight).round(6)
      end

      def select_results(scored_results)
        eligible =
          scored_results.select do |item|
            item.cross_encoder_score >=
              minimum_score
          end

        candidates =
          eligible.presence ||
          scored_results

        candidates
          .sort_by do |item|
            [
              -item.combined_score,
              -item.cross_encoder_score,
              -item.retrieval_score,
              item.chunk.id
            ]
          end
          .first(rerank_limit)
      end

      def build_scores(scored_results)
        scored_results.each_with_object({}) do |item, hash|
          hash[item.chunk.id] = {
            cross_encoder_score:
              item.cross_encoder_score,
            cross_encoder_reason:
              item.cross_encoder_reason,
            retrieval_score:
              item.retrieval_score,
            combined_score:
              item.combined_score
          }
        end
      end

      def average_cross_encoder_score(scored_results)
        return 0.0 if scored_results.empty?

        total =
          scored_results.sum(
            &:cross_encoder_score
          )

        (total / scored_results.size).round(6)
      end

      def monotonic_time
        Process.clock_gettime(
          Process::CLOCK_MONOTONIC
        )
      end

      def elapsed_ms(started_at)
        (
          (
            monotonic_time - started_at
          ) * 1_000
        ).round(2)
      end
    end
  end
end
