# frozen_string_literal: true

module Ai
  # Implementação de teste de Ai::VectorStoreService: mesma interface,
  # sem HTTP. Cada teste instancia a sua própria (`Ai::InMemoryVectorStore.new`),
  # o que já garante isolamento entre testes rodando em paralelo. O score
  # de "search" é o cosseno real entre os vetores, igual ao que o Qdrant
  # retorna pra uma coleção configurada com distância Cosine.
  class InMemoryVectorStore
    Point = Ai::VectorStoreService::Point

    def initialize
      @collections = Hash.new { |hash, key| hash[key] = {} }
    end

    def ensure_collection!(collection:, size: nil, distance: nil)
      @collections[collection]
    end

    def upsert(collection:, id:, vector:, payload: {})
      @collections[collection][id] = { vector: vector, payload: payload }
    end

    def upsert_batch(collection:, points:)
      points.each do |point|
        point = point.to_h if point.is_a?(Point)

        upsert(
          collection: collection,
          id: point.fetch(:id),
          vector: point.fetch(:vector),
          payload: point.fetch(:payload, {})
        )
      end
    end

    def search(collection:, vector:, limit:, ids: nil, with_vector: false)
      candidates(collection, ids)
        .map do |id, entry|
          Point.new(
            id: id,
            vector: with_vector ? entry[:vector] : nil,
            payload: entry[:payload],
            score: cosine_similarity(vector, entry[:vector])
          )
        end
        .sort_by { |point| -point.score }
        .first(limit)
    end

    def retrieve(collection:, ids:, with_vector: true)
      ids.filter_map do |id|
        entry = @collections[collection][id]

        next unless entry

        Point.new(
          id: id,
          vector: with_vector ? entry[:vector] : nil,
          payload: entry[:payload],
          score: nil
        )
      end
    end

    def delete(collection:, ids: nil, filter: nil)
      store = @collections[collection]

      if ids
        ids.each { |id| store.delete(id) }
      elsif filter
        store.reject! do |_id, entry|
          filter.all? { |key, value| entry[:payload][key.to_s] == value || entry[:payload][key] == value }
        end
      end
    end

    private

    def candidates(collection, ids)
      store = @collections[collection]

      return store unless ids

      allowed = ids.map(&:to_i)
      store.select { |id, _entry| allowed.include?(id.to_i) }
    end

    def cosine_similarity(vector_a, vector_b)
      return 0.0 if vector_a.nil? || vector_b.nil?
      return 0.0 unless vector_a.size == vector_b.size

      dot_product = 0.0
      norm_a = 0.0
      norm_b = 0.0

      vector_a.each_index do |index|
        value_a = vector_a[index].to_f
        value_b = vector_b[index].to_f

        dot_product += value_a * value_b
        norm_a += value_a * value_a
        norm_b += value_b * value_b
      end

      denominator = Math.sqrt(norm_a) * Math.sqrt(norm_b)

      return 0.0 if denominator.zero?

      dot_product / denominator
    end
  end
end
