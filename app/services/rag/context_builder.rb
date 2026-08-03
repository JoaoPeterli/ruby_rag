module Rag
  class ContextBuilder
    def self.call(chunks)
      new(chunks).call
    end

    def initialize(chunks)
      @chunks = chunks
    end

    def call
      @chunks.map.with_index do |chunk, index|
        <<~TEXT
        Documento #{index + 1}

        #{chunk.content}

        ----------------------------------------
        TEXT
      end.join("\n")
    end
  end
end
