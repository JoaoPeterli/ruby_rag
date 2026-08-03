ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Não usamos fixtures :all: o bulk loader do Rails desativa
    # triggers do Postgres (disable_referential_integrity) pra
    # carregar mais rápido, o que quebra o trigger que preenche
    # document_chunks.search_vector. Em vez disso, os testes criam
    # registros diretamente (Document.create!, DocumentChunk.create!),
    # passando pelos callbacks/triggers normalmente.

    # Add more helper methods to be used by all tests here...
  end
end
