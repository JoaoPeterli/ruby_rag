# frozen_string_literal: true

module Documents
  module ContextCompression
    Result = Data.define(
      :chunks,
      :removed_chunks,
      :scores,
      :original_count,
      :compressed_count,
      :compression_ratio,
      :duration_ms,
      :strategy
    ) do
      def compressed?
        compressed_count < original_count
      end

      def removed_count
        original_count - compressed_count
      end

      def empty?
        chunks.empty?
      end
    end
  end
end
