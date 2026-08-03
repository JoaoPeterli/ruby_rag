module Documents
  class PromptBuilder
    SYSTEM_PROMPT = <<~PROMPT.freeze
      Você é um assistente especializado em responder perguntas usando
      exclusivamente o contexto fornecido.

      Regras obrigatórias:

      1. Use apenas informações presentes nas fontes fornecidas.
      2. Não invente dados, regras, nomes, datas ou procedimentos.
      3. Quando o contexto não for suficiente, informe claramente que
         não encontrou informações suficientes para responder.
      4. Cite as fontes usadas no formato [FONTE N].
      5. Não mencione documentos ou fontes que não tenham sido utilizados.
      6. Diferencie informações explícitas de conclusões ou inferências.
      7. Responda em português do Brasil.
      8. Seja claro, objetivo e tecnicamente preciso.
    PROMPT

    Result = Data.define(
      :messages,
      :system_prompt,
      :user_prompt,
      :context_included,
      :sources_count
    )

    class Error < StandardError; end
    class EmptyQuestionError < Error; end
    class InvalidContextResultError < Error; end
    class EmptyContextError < Error; end

    def self.call(question:, context_result:, conversation_history: [])
      new(
        question: question,
        context_result: context_result,
        conversation_history: conversation_history
      ).call
    end

    def initialize(question:, context_result:, conversation_history: [])
      @question = question.to_s.strip
      @context_result = context_result
      @conversation_history = Array(conversation_history)
    end

    def call
      validate!

      system_prompt = SYSTEM_PROMPT
      user_prompt = build_user_prompt

      Result.new(
        messages: build_messages(
          system_prompt,
          user_prompt
        ),
        system_prompt: system_prompt,
        user_prompt: user_prompt,
        context_included: true,
        sources_count: context_result.sources.length
      )
    end

    private

    attr_reader :question,
                :context_result,
                :conversation_history

    def validate!
      validate_question!
      validate_context_result!
      validate_context_presence!
    end

    def validate_question!
      return if question.present?

      raise EmptyQuestionError,
            "A pergunta não pode estar vazia."
    end

    def validate_context_result!
      return if context_result.is_a?(
        Documents::ContextBuilder::Result
      )

      raise InvalidContextResultError,
            "context_result precisa ser um ContextBuilder::Result."
    end

    def validate_context_presence!
      return if context_result.context.present?

      raise EmptyContextError,
            "Não existem fontes suficientes para montar o prompt."
    end

    def build_user_prompt
      <<~PROMPT.strip
        CONTEXTO RECUPERADO:

        #{context_result.context}

        PERGUNTA DO USUÁRIO:

        #{question}

        INSTRUÇÕES PARA A RESPOSTA:

        - Responda somente com base no contexto recuperado.
        - Cite cada afirmação relevante usando [FONTE N], uma citação por
          colchete (ex: [FONTE 1][FONTE 3]). Nunca agrupe números no mesmo
          colchete (evite [FONTE 1, 3] ou [FONTE 1 a 3]).
        - Caso as fontes não sejam suficientes, diga explicitamente:
          "Não encontrei informações suficientes nas fontes fornecidas."
        - Não complete informações ausentes usando conhecimento externo.
      PROMPT
    end

    def build_messages(system_prompt, user_prompt)
      [
        {
          role: "system",
          content: system_prompt
        },
        *history_messages,
        {
          role: "user",
          content: user_prompt
        }
      ]
    end

    def history_messages
      conversation_history.filter_map do |turn|
        role = normalize_role(turn[:role] || turn["role"])
        content = (turn[:content] || turn["content"]).to_s.strip

        next if role.nil? || content.blank?

        {
          role: role,
          content: content
        }
      end
    end

    def normalize_role(value)
      role = value.to_s.strip

      return role if %w[user assistant].include?(role)

      nil
    end
  end
end
