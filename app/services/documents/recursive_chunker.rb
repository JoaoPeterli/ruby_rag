module Documents
  class RecursiveChunker
    DEFAULT_MAX_SIZE = 1000

    SEPARATORS = [
      /\n#{'#'}/,   # Markdown
      /\n{2,}/,     # Parágrafos
      /\. /,        # Frases
      /\n/,         # Linhas
      / /           # Espaços
    ].freeze

    def self.call(text)
      new(text).call
    end

    def initialize(text)
      @text = text.to_s.strip
    end

    def call
      split(@text, SEPARATORS)
    end

    private

    def split(text, separators)
      return [text] if text.length <= DEFAULT_MAX_SIZE

      separator = separators.first

      return hard_split(text) if separator.nil?

      parts = text.split(separator)

      chunks = []

      parts.each do |part|
        if part.length <= DEFAULT_MAX_SIZE
          chunks << part
        else
          chunks.concat(
            split(part, separators.drop(1))
          )
        end
      end

      chunks
    end

    def hard_split(text)
      text.scan(/.{1,#{DEFAULT_MAX_SIZE}}/m)
    end
  end
end
