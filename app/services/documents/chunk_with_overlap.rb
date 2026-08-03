module Documents
  class ChunkWithOverlap
    attr_reader :content, :overlap

    def initialize(content:, overlap: nil)
      @content = normalize(content)
      @overlap = normalize(overlap)
    end

    def text(separator: "\n\n")
      return content if overlap.empty?

      "#{overlap}#{separator}#{content}"
    end

    def overlap?
      !overlap.empty?
    end

    private

    def normalize(value)
      value.to_s.strip
    end
  end
end
