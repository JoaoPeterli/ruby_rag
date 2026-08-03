module Documents
  class Chunker
    DEFAULT_SIZE = 1000
    DEFAULT_OVERLAP = 200

    def self.call(text)
      new(text).call
    end

    def initialize(text, size: DEFAULT_SIZE, overlap: DEFAULT_OVERLAP)
      @text = text.to_s
      @size = size
      @overlap = overlap
    end

    def call
      chunks = []

      split_paragraphs.each do |paragraph|
        chunks.concat(chunk_paragraph(paragraph))
      end

      chunks
    end

    private

    def split_paragraphs
      @text.split(/\n{2,}/)
    end

    def chunk_paragraph(paragraph)
      chunks = []

      start = 0

      while start < paragraph.length
        finish = start + @size

        chunks << paragraph[start...finish]

        start += (@size - @overlap)
      end

      chunks
    end
  end
end
