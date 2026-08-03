# frozen_string_literal: true

module Documents
  class RecordFeedbackService
    class Error < StandardError; end
    class InvalidRatingError < Error; end
    class AnswerNotFoundError < Error; end

    def self.call(...)
      new(...).call
    end

    def initialize(rag_answer_id:, rating:, reason: nil, account_id: nil)
      @rag_answer_id = rag_answer_id
      @rating = rating.to_s
      @reason = reason
      @account_id = account_id
    end

    def call
      validate!

      rag_answer.rag_feedbacks.create!(
        rating: rating,
        reason: reason.presence
      )
    end

    private

    attr_reader :rag_answer_id, :rating, :reason, :account_id

    def validate!
      unless RagFeedback::RATINGS.include?(rating)
        raise InvalidRatingError,
              "rating deve ser um de: #{RagFeedback::RATINGS.join(', ')}"
      end

      return if rag_answer

      # Mesma mensagem tanto pra "não existe" quanto pra "existe mas é
      # de outra conta" — não dá pra vazar pra fora que existe uma
      # resposta de outra conta com esse id.
      raise AnswerNotFoundError,
            "Nenhuma resposta encontrada com id #{rag_answer_id}"
    end

    def rag_answer
      return @rag_answer if defined?(@rag_answer)

      answer = RagAnswer.find_by(id: rag_answer_id)

      @rag_answer = answer if answer && owned_by_account?(answer)
    end

    def owned_by_account?(answer)
      return true if account_id.nil?

      answer.rag_query&.account_id == account_id
    end
  end
end
