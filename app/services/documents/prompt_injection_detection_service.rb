# frozen_string_literal: true

module Documents
  # Heurísticas de detecção, não um classificador semântico. O objetivo é
  # sinalizar para revisão (defesa em profundidade), não bloquear a
  # ingestão automaticamente — falsos positivos em documentos de negócio
  # legítimos (ex: "ignore a fatura anterior") são esperados.
  #
  # A defesa principal continua sendo o prompt dos serviços que consomem
  # o conteúdo dos chunks (CrossEncoder, HallucinationCheck já instruem o
  # modelo a nunca seguir instruções vindas do conteúdo).
  class PromptInjectionDetectionService
    PATTERNS = {
      instruction_override: [
        /ignor[ea]\s+(todas\s+)?(as\s+)?instru[çc][õo]es/i,
        /desconsidere\s+(o\s+que\s+foi\s+dito|as\s+instru[çc][õo]es)/i,
        /ignore\s+(all\s+)?(previous|prior|above)\s+instructions/i,
        /disregard\s+(the\s+)?(above|previous|prior)/i
      ],
      role_hijack: [
        /voc[êe]\s+(agora\s+)?[ée]\s+um[a]?\s+assistente/i,
        /you\s+are\s+now\s+(a|an)\s+/i,
        /act\s+as\s+(if\s+you\s+are\s+)?/i,
        /finja\s+ser/i
      ],
      system_prompt_leak: [
        /\[\s*system\s*\]\s*:/i,
        /\[\s*sistema\s*\]\s*:/i,
        /repita\s+(o\s+)?(seu\s+)?prompt/i,
        /reveal\s+your\s+(system\s+)?prompt/i,
        /what\s+(are\s+)?your\s+instructions/i
      ],
      hidden_content: [
        /[\u200B\u200C\u200D\uFEFF]/,
        /<!--.*?-->/m
      ]
    }.freeze

    WEIGHT_PER_CATEGORY = {
      instruction_override: 0.4,
      role_hijack: 0.25,
      system_prompt_leak: 0.25,
      hidden_content: 0.3
    }.freeze

    Match = Data.define(:category, :excerpt)
    Result = Data.define(:suspicious, :risk_score, :matches)

    class Error < StandardError; end
    class InvalidContentError < Error; end

    def self.call(...)
      new(...).call
    end

    def initialize(content:)
      @content = content
    end

    def call
      validate!

      matches = detect_matches

      Result.new(
        suspicious: matches.any?,
        risk_score: calculate_risk_score(matches),
        matches: matches
      )
    end

    private

    attr_reader :content

    def validate!
      return if content.is_a?(String)

      raise InvalidContentError, "content deve ser uma string"
    end

    def detect_matches
      PATTERNS.each_with_object([]) do |(category, patterns), matches|
        patterns.each do |pattern|
          match = content.match(pattern)

          next unless match

          matches << Match.new(
            category: category,
            excerpt: excerpt_around(match)
          )
        end
      end
    end

    def excerpt_around(match)
      start_index = [ match.begin(0) - 30, 0 ].max
      end_index = [ match.end(0) + 30, content.length ].min

      content[start_index...end_index].strip
    end

    def calculate_risk_score(matches)
      return 0.0 if matches.empty?

      categories = matches.map(&:category).uniq

      score = categories.sum { |category| WEIGHT_PER_CATEGORY.fetch(category, 0.2) }

      score.clamp(0.0, 1.0).round(4)
    end
  end
end
