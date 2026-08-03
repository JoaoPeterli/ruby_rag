module Rag
  class PromptBuilder
    def self.call(question:, context:)
      <<~PROMPT
      Você é um assistente especializado.

      Responda apenas utilizando o contexto abaixo.

      Se a resposta não estiver presente no contexto, responda:

      "Não encontrei essa informação na base de conhecimento."

      CONTEXTO

      #{context}

      PERGUNTA

      #{question}
      PROMPT
    end
  end
end
