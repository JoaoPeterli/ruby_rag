# frozen_string_literal: true

module Documents
  module Pipeline
    class Pipeline
      def self.call(...)
        new(...).call
      end

      def initialize(
        context:,
        steps:
      )
        @context = context
        @steps = steps
      end

      def call
        steps.each do |step|
          step.call(context: context)
        end

        context
      end

      private

      attr_reader :context, :steps
    end
  end
end
