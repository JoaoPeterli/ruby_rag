module Documents
  class OverlapService
    DEFAULT_OVERLAP_SIZE = 150

    SEPARATORS = [
      /\n{2,}/,          # Parágrafos
      /(?<=[.!?])\s+/,   # Frases
      /\n+/,              # Linhas
      /\s+/               # Palavras
    ].freeze

    def self.call(chunks, overlap_size: DEFAULT_OVERLAP_SIZE)
      new(
        chunks,
        overlap_size: overlap_size
      ).call
    end

    def initialize(chunks, overlap_size:)
      @chunks = Array(chunks)
      @overlap_size = overlap_size
    end

    def call
      return [] if @chunks.empty?
      return @chunks if @chunks.one?

      result = [@chunks.first.to_s.strip]

      @chunks.each_cons(2) do |previous_chunk, current_chunk|
        overlap = build_overlap(previous_chunk)

        result << join_chunks(
          overlap,
          current_chunk
        )
      end

      result
    end

    private

    def build_overlap(text)
      text = text.to_s.strip

      return "" if text.empty?

      SEPARATORS.each do |separator|
        overlap = extract_complete_parts(
          text,
          separator
        )

        return overlap unless overlap.empty?
      end

      hard_overlap(text)
    end

    def extract_complete_parts(text, separator)
      parts = text
        .split(separator)
        .map(&:strip)
        .reject(&:empty?)

      selected_parts = []
      current_size = 0

      parts.reverse_each do |part|
        separator_size = selected_parts.empty? ? 0 : 2
        candidate_size = current_size + separator_size + part.length

        break if candidate_size > @overlap_size

        selected_parts.unshift(part)
        current_size = candidate_size
      end

      selected_parts.join("\n\n")
    end

    def hard_overlap(text)
      text.last(@overlap_size)
    end

    def join_chunks(overlap, current_chunk)
      current_chunk = current_chunk.to_s.strip

      return current_chunk if overlap.empty?

      "#{overlap}\n\n#{current_chunk}"
    end
  end
end
