# frozen_string_literal: true

namespace :qdrant do
  desc "Cria (se ainda não existirem) as coleções usadas pelo Qdrant"
  task setup: :environment do
    store = Ai::VectorStoreService.default

    store.ensure_collection!(
      collection: Ai::Configuration::QDRANT_DOCUMENT_CHUNKS_COLLECTION,
      size: Ai::Configuration::QDRANT_VECTOR_SIZE
    )

    store.ensure_collection!(
      collection: Ai::Configuration::QDRANT_SEMANTIC_CACHE_COLLECTION,
      size: Ai::Configuration::QDRANT_VECTOR_SIZE
    )

    puts "Coleções do Qdrant prontas: " \
         "#{Ai::Configuration::QDRANT_DOCUMENT_CHUNKS_COLLECTION}, " \
         "#{Ai::Configuration::QDRANT_SEMANTIC_CACHE_COLLECTION}"
  end
end
