# frozen_string_literal: true

module Documents
  module CitationEngine
    class Service
      SOURCE_NUMBER_PATTERN = /\[FONTE\s+([^\]]+)\]/i

      class Error < StandardError; end
      class InvalidAnswerError < Error; end
      class InvalidSourcesError < Error; end

      def self.call(...)
        new(...).call
      end

      def initialize(answer:, sources:)
        @answer = answer
        @sources = sources
      end

      def call
        started_at = monotonic_time

        validate!

        citations = build_citations

        Result.new(
          answer: answer,
          citations: citations,
          cited_source_numbers: citations.map(&:source_number).uniq.sort,
          uncited_source_numbers: uncited_source_numbers(citations),
          citation_count: citations.size,
          source_count: sources.size,
          citation_coverage: citation_coverage(citations),
          duration_ms: elapsed_ms(started_at)
        )
      end

      private

      attr_reader :answer, :sources

      def validate!
        unless answer.is_a?(String)
          raise InvalidAnswerError, "answer deve ser uma string"
        end

        return if sources.is_a?(Array)

        raise InvalidSourcesError, "sources deve ser um array"
      end

      def build_citations
        extract_source_numbers.filter_map do |number|
          source = find_source(number)

          next unless source

          Citation.new(
            source_number: number,
            chunk_id: source_attribute(source, :chunk_id),
            document_id: source_attribute(source, :document_id),
            position: source_attribute(source, :position)
          )
        end
      end

      def extract_source_numbers
        answer
          .to_s
          .scan(SOURCE_NUMBER_PATTERN)
          .flat_map { |match| parse_source_number_group(match.first) }
          .uniq
      end

      def parse_source_number_group(text)
        text.split(",").flat_map do |segment|
          parse_segment(segment.strip)
        end
      end

      def parse_segment(segment)
        case segment
        when /\A(\d+)\s*a\s*(\d+)\z/i
          (Regexp.last_match(1).to_i..Regexp.last_match(2).to_i).to_a
        when /\A\d+\z/
          [ segment.to_i ]
        else
          segment.scan(/\d+/).map(&:to_i)
        end
      end

      def find_source(number)
        sources.find do |source|
          source_attribute(source, :source_number) == number
        end
      end

      def source_attribute(source, attribute)
        if source.is_a?(Hash)
          source[attribute] || source[attribute.to_s]
        else
          source.public_send(attribute)
        end
      end

      def uncited_source_numbers(citations)
        cited = citations.map(&:source_number)

        sources
          .map { |source| source_attribute(source, :source_number) }
          .reject { |number| cited.include?(number) }
      end

      def citation_coverage(citations)
        return 0.0 if sources.empty?

        (citations.map(&:source_number).uniq.size.to_f / sources.size).round(4)
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
