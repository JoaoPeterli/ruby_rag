# frozen_string_literal: true

module Documents
  module Pipeline
    module Steps
      class CrossEncoderRerankStep < Step
        include TracksStageFailures

        def initialize(
          context:,
          cross_encoder_service:
            Documents::CrossEncoder::Service,
          strategy:
            Documents::CrossEncoder::LlmBatchStrategy,
          logger: Rails.logger
        )
          super(context:)

          @cross_encoder_service = cross_encoder_service
          @strategy = strategy
          @logger = logger
        end

        def call
          input_results = available_results

          unless context.metadata[:cross_encoder_enabled]
            context.cross_encoder_results = input_results

            return
          end

          if input_results.blank?
            context.cross_encoder_results = []

            return
          end

          cross_encoder_result =
            cross_encoder_service.call(
              question: context.question,
              results: input_results,
              candidate_limit:
                context.metadata.fetch(:cross_encoder_candidate_limit),
              rerank_limit:
                context.metadata.fetch(:cross_encoder_rerank_limit),
              minimum_score:
                context.metadata.fetch(:cross_encoder_minimum_score),
              cross_encoder_weight:
                context.metadata.fetch(:cross_encoder_weight),
              retrieval_weight:
                context.metadata.fetch(:cross_encoder_retrieval_weight),
              strategy: strategy,
              strategy_options: {
                batch_size:
                  context.metadata.fetch(:cross_encoder_batch_size)
              }
            )

          context.cross_encoder = cross_encoder_result
          context.cross_encoder_results = cross_encoder_result.results

          add_metrics(cross_encoder_result)
        rescue Documents::CrossEncoder::Service::Error => error
          record_stage_failure(stage: "cross_encoder", error: error)

          logger.warn(
            {
              event: "pipeline.cross_encoder_failure",
              question: context.question,
              error_class: error.class.name,
              error_message: error.message
            }.to_json
          )

          context.cross_encoder_results = available_results
        end

        private

        attr_reader(
          :cross_encoder_service,
          :strategy,
          :logger
        )

        def available_results
          return context.reranked_results if context.reranked_results.present?
          return context.merged_results if context.merged_results.present?

          context.hybrid_results.values.flatten
        end

        def add_metrics(result)
          context.metrics[:cross_encoder_duration_ms] =
            result.duration_ms

          context.metrics[:cross_encoder_input_count] =
            result.original_count

          context.metrics[:cross_encoder_evaluated_count] =
            result.evaluated_count

          context.metrics[:cross_encoder_output_count] =
            result.reranked_count

          context.metrics[:cross_encoder_average_score] =
            result.average_score

          context.metrics[:cross_encoder_model] =
            result.model

          context.metrics[:cross_encoder_strategy] =
            result.strategy
        end
      end
    end
  end
end
