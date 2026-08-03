module Rag 
  class AnswerService 
    DEFAULT_LIMIT = 5

    def self.call(question:)
      new(question).call
    end

    def initialize(question)
      @question = question
    end

    def call 
      chunks = Rag::SearchService.call(
        question: @question,
        limit: DEFAULT_LIMIT
      )

      context = Rag::ContextBuilder.call(chunks)

      prompt = Rag::PromptBuilder.call(
        question: @question,
        context: context
      )

      Ai::ChatService.call(prompt)
    end
  end
end
