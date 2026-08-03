# frozen_string_literal: true

module Documents
  module ContextCompression
    class Strategy
      class Error < StandardError; end
      class InvalidQuestionError < Error; end
      class InvalidChunksError < Error; end
      class InvalidEmbeddingError < Error; end

      def self.call(...)
        new(...).call
      end

      def initialize(
        question:,
        chunks:,
        query_embedding:
      )
        @question = question
        @chunks = chunks
        @query_embedding = query_embedding
      end

      def call
        raise NotImplementedError,
              "#{self.class.name} precisa implementar #call"
      end

      private

      attr_reader(
        :question,
        :chunks,
        :query_embedding
      )

      def validate!
        validate_question!
        validate_chunks!
        validate_query_embedding!
      end

      def validate_question!
        return if question.is_a?(String) &&
                  question.strip.present?

        raise InvalidQuestionError,
              "question deve ser uma string não vazia"
      end

      def validate_chunks!
        valid =
          chunks.is_a?(Array) &&
          chunks.all? do |chunk|
            chunk.respond_to?(:id) &&
              chunk.respond_to?(:content) &&
              chunk.respond_to?(:embedding)
          end

        return if valid

        raise InvalidChunksError,
              "chunks deve ser um array de DocumentChunk"
      end

      def validate_query_embedding!
        valid =
          query_embedding.respond_to?(:to_a) &&
          query_embedding.to_a.any?

        return if valid

        raise InvalidEmbeddingError,
              "query_embedding deve possuir valores"
      end
    end
  end
end
