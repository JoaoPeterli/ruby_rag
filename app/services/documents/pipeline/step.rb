# frozen_string_literal: true

module Documents
  module Pipeline
    class Step
      def self.call(...)
        new(...).call
      end

      def initialize(context:)
        @context = context
      end

      private

      attr_reader :context

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def elapsed_ms(started_at)
        ((monotonic_time - started_at) * 1_000).round(2)
      end
    end
  end
end
