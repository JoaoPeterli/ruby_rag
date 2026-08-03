# frozen_string_literal: true

module Documents
  module Evaluation
    class Service
      SUMMARY_METRIC_KEYS = %w[
        retrieval_precision
        retrieval_recall
        chunk_relevance
        answer_faithfulness
        citation_coverage
      ].freeze

      class Error < StandardError; end

      def self.call(...)
        new(...).call
      end

      def initialize(
        cases: RagEvalCase.active,
        question_answering_service: Documents::QuestionAnsweringService,
        metrics_calculator: Documents::Evaluation::MetricsCalculator,
        logger: Rails.logger
      )
        @cases = cases
        @question_answering_service = question_answering_service
        @metrics_calculator = metrics_calculator
        @logger = logger
      end

      def call
        run = RagEvalRun.create!(
          started_at: Time.current,
          cases_count: cases.count
        )

        results = cases.map { |eval_case| evaluate_case(run: run, eval_case: eval_case) }

        run.update!(
          finished_at: Time.current,
          summary: build_summary(results)
        )

        run
      end

      private

      attr_reader(
        :cases,
        :question_answering_service,
        :metrics_calculator,
        :logger
      )

      def evaluate_case(run:, eval_case:)
        started_at = monotonic_time

        answer_result = question_answering_service.call(
          question: eval_case.question,
          hallucination_check_enabled: true
        )

        metrics = metrics_calculator.call(
          eval_case: eval_case,
          answer_result: answer_result
        )

        RagEvalResult.create!(
          rag_eval_run: run,
          rag_eval_case: eval_case,
          answer: answer_result.answer,
          metrics: metrics.to_h,
          duration_ms: elapsed_ms(started_at),
          errored: false
        )
      rescue StandardError => error
        record_case_error(run: run, eval_case: eval_case, error: error, started_at: started_at)
      end

      def record_case_error(run:, eval_case:, error:, started_at:)
        logger.warn(
          {
            event: "rag_evaluation.case_failure",
            eval_case_id: eval_case.id,
            error_class: error.class.name,
            error_message: error.message
          }.to_json
        )

        RagEvalResult.create!(
          rag_eval_run: run,
          rag_eval_case: eval_case,
          errored: true,
          error_message: error.message,
          duration_ms: elapsed_ms(started_at)
        )
      end

      def build_summary(results)
        successful = results.reject(&:errored)

        averages =
          SUMMARY_METRIC_KEYS.index_with do |key|
            average_metric(successful, key)
          end

        {
          cases_count: results.size,
          errored_count: results.count(&:errored),
          no_evidence_accuracy: no_evidence_accuracy(successful)
        }.merge(averages)
      end

      def average_metric(results, key)
        values = results.filter_map { |result| result.metrics[key] }

        return if values.empty?

        (values.sum.to_f / values.size).round(4)
      end

      def no_evidence_accuracy(results)
        values = results.filter_map { |result| result.metrics["no_evidence_correct"] }

        return if values.empty?

        (values.count { |value| value }.to_f / values.size).round(4)
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def elapsed_ms(started_at)
        ((monotonic_time - started_at) * 1_000).round(2)
      end
    end
  end
end
