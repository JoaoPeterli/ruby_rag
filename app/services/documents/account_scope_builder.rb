# frozen_string_literal: true

module Documents
  # Fronteira de segurança, separada do MetadataScopeBuilder (que é
  # sobre relevância, não sobre autorização). É aplicada sempre, antes
  # de qualquer outro filtro — mesmo que o filtro de metadados tenha um
  # bug, o escopo de conta continua valendo.
  #
  # account_id: nil é modo "sem restrição" (uso interno/console/testes,
  # nunca alcançável a partir de uma requisição HTTP — a API sempre
  # passa um account_id explícito).
  class AccountScopeBuilder
    def self.call(scope: DocumentChunk.all, account_id: nil)
      return scope if account_id.nil?

      scope.where(account_id: account_id)
    end
  end
end
