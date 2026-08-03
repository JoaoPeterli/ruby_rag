# frozen_string_literal: true

module Documents
  module Evaluation
    class MetricsCalculator
      class Error < StandardError; end
      class InvalidEvalCaseError < Error; end
      class InvalidAnswerResultError < Error; end

      def self.call(...)
        new(...).call
      end

      def initialize(eval_case:, answer_result:)
        @eval_case = eval_case
        @answer_result = answer_result
      end

      def call
        validate!

        Metrics.new(
          retrieval_precision: retrieval_precision,
          retrieval_recall: retrieval_recall,
          chunk_relevance: chunk_relevance,
          answer_faithfulness: answer_faithfulness,
          citation_coverage: answer_result.citation_coverage,
          no_evidence_correct: no_evidence_correct?
        )
      end

      private

      attr_reader :eval_case, :answer_result

      def validate!
        unless eval_case.is_a?(RagEvalCase)
          raise InvalidEvalCaseError, "eval_case deve ser um RagEvalCase"
        end

        return if answer_result.is_a?(Documents::QuestionAnsweringService::Result)

        raise InvalidAnswerResultError,
              "answer_result deve ser um Documents::QuestionAnsweringService::Result"
      end

      def retrieved_chunk_ids
        @retrieved_chunk_ids ||= answer_result.sources.map(&:chunk_id)
      end

      def expected_chunk_ids
        @expected_chunk_ids ||= Array(eval_case.expected_chunk_ids).map(&:to_i)
      end

      def retrieval_precision
        return if expected_chunk_ids.empty?
        return 0.0 if retrieved_chunk_ids.empty?

        matches = (retrieved_chunk_ids & expected_chunk_ids).size

        (matches.to_f / retrieved_chunk_ids.size).round(4)
      end

      def retrieval_recall
        return if expected_chunk_ids.empty?

        matches = (retrieved_chunk_ids & expected_chunk_ids).size

        (matches.to_f / expected_chunk_ids.size).round(4)
      end

      def chunk_relevance
        scores =
          answer_result.sources.filter_map do |source|
            source.combined_score ||
              source.cross_encoder_score ||
              source.rerank_score
          end

        return if scores.empty?

        (scores.sum.to_f / scores.size).round(4)
      end

      def answer_faithfulness
        hallucination_check = answer_result.hallucination_check

        return unless hallucination_check

        (1.0 - hallucination_check.hallucination_rate).round(4)
      end

      def no_evidence_correct?
        if eval_case.expects_answer?
          !answer_result.refused
        else
          !!answer_result.refused
        end
      end
    end
  end
end
