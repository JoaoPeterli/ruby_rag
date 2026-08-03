# frozen_string_literal: true

module Documents
  module Pipeline
    # Contexto mutável do pipeline de resposta (QuestionAnsweringService),
    # análogo ao Documents::Pipeline::Context usado pelo pipeline de
    # retrieval, mas com o shape específico de pergunta -> resposta.
    #
    # `result` funciona como marcador de "atalho": assim que um step
    # define context.result (cache hit ou "sem evidência"), os steps
    # seguintes que fazem trabalho real (retrieval, prompt, LLM,
    # citações, etc.) devem checar `return if context.result` logo no
    # início e não fazer nada — só StoreCacheStep (com sua própria regra:
    # pula quando é cache_hit) e PersistStep continuam rodando sempre.
    class AnswerContext
      attr_accessor \
        :question,
        :account_id,
        :conversation_history,
        :config,
        :on_delta,
        :started_at,
        :normalized_question,
        :effective_question,
        :query_rewrite_result,
        :question_embedding,
        :cache_hit,
        :route_query,
        :adaptive_plan,
        :token_budget,
        :retrieval_result,
        :context_result,
        :prompt,
        :chat_result,
        :citation_result,
        :groundedness_result,
        :hallucination_result,
        :confidence_result,
        :result

      def initialize(
        question:,
        account_id:,
        conversation_history:,
        config:,
        on_delta:,
        started_at:
      )
        @question = question
        @account_id = account_id
        @conversation_history = conversation_history
        @config = config
        @on_delta = on_delta
        @started_at = started_at
      end
    end
  end
end
