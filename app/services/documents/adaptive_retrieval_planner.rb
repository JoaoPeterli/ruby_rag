# frozen_string_literal: true

module Documents
  class AdaptiveRetrievalPlanner
    SIMPLE_WORD_THRESHOLD = 6

    COMPLEX_KEYWORDS = %w[
      compare comparar comparação diferença diferenças versus
      relação combinar todos todas histórico evolução
    ].freeze

    SUMMARY_KEYWORDS = %w[
      resuma resumo resumir sintetize síntese visão geral
    ].freeze

    Plan = Data.define(
      :query_expansion_enabled,
      :multi_query_enabled,
      :metadata_extraction_enabled,
      :cross_encoder_enabled,
      :parent_retrieval_enabled,
      :context_compression_enabled,
      :complexity
    )

    class Error < StandardError; end
    class InvalidQuestionError < Error; end

    def self.call(...)
      new(...).call
    end

    def initialize(question:, category: nil)
      @question = question
      @category = category&.to_s
    end

    def call
      validate!

      plan_for(complexity)
    end

    private

    attr_reader :question, :category

    def validate!
      return if question.is_a?(String) && question.strip.present?

      raise InvalidQuestionError, "question deve ser uma string não vazia"
    end

    def normalized_question
      @normalized_question ||= question.strip.downcase
    end

    # Se o Query Router (aula 42) já classificou a pergunta, usamos a
    # categoria dele — é mais confiável que a heurística de palavras.
    # Sem o router (padrão), caímos na heurística local, que é grátis.
    def complexity
      return complexity_for_category if category.present?

      heuristic_complexity
    end

    def complexity_for_category
      case category
      when "fora_da_base", "factual"
        :simple
      when "comparacao", "resumo"
        :complex
      else
        :standard
      end
    end

    def heuristic_complexity
      return :complex if complex_keywords?
      return :simple if short_question?

      :standard
    end

    def complex_keywords?
      (COMPLEX_KEYWORDS + SUMMARY_KEYWORDS).any? do |keyword|
        normalized_question.include?(keyword)
      end
    end

    def short_question?
      normalized_question.split(/\s+/).size <= SIMPLE_WORD_THRESHOLD
    end

    def plan_for(complexity)
      case complexity
      when :simple
        simple_plan
      when :complex
        complex_plan
      else
        standard_plan
      end
    end

    # Pergunta curta e direta: pula expansão/multi-query (o ganho não
    # compensa a latência) mas mantém filtros de metadados e vizinhos
    # de documento, que são baratos e ajudam a precisão.
    def simple_plan
      Plan.new(
        query_expansion_enabled: false,
        multi_query_enabled: false,
        metadata_extraction_enabled: true,
        cross_encoder_enabled: false,
        parent_retrieval_enabled: true,
        context_compression_enabled: false,
        complexity: :simple
      )
    end

    def standard_plan
      Plan.new(
        query_expansion_enabled: true,
        multi_query_enabled: false,
        metadata_extraction_enabled: true,
        cross_encoder_enabled: true,
        parent_retrieval_enabled: true,
        context_compression_enabled: true,
        complexity: :standard
      )
    end

    # Comparação/resumo: precisa reunir mais candidatos de fontes
    # diferentes (multi-query) e o cross encoder ajuda a manter só o
    # que é relevante depois de juntar tanta coisa.
    def complex_plan
      Plan.new(
        query_expansion_enabled: true,
        multi_query_enabled: true,
        metadata_extraction_enabled: true,
        cross_encoder_enabled: true,
        parent_retrieval_enabled: true,
        context_compression_enabled: true,
        complexity: :complex
      )
    end
  end
end
