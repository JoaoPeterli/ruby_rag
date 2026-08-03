# frozen_string_literal: true

module Documents
  module CrossEncoder
    class Strategy
      class Error < StandardError; end
      class InvalidQuestionError < Error; end
      class InvalidResultsError < Error; end

      def self.call(...)
        new(...).call
      end

      def initialize(question:, results:)
        @question = question
        @results = results
      end

      def call
        raise NotImplementedError,
              "#{self.class.name} precisa implementar #call"
      end

      private

      attr_reader :question, :results

      def validate!
        validate_question!
        validate_results!
      end

      def validate_question!
        return if question.is_a?(String) &&
                  question.strip.present?

        raise InvalidQuestionError,
              "question deve ser uma string não vazia"
      end

      def validate_results!
        valid =
          results.is_a?(Array) &&
          results.all? do |result|
            result.respond_to?(:chunk) &&
              result.chunk.respond_to?(:id) &&
              result.chunk.respond_to?(:content)
          end

        return if valid

        raise InvalidResultsError,
              "results deve conter resultados com chunks válidos"
      end
    end
  end
end
