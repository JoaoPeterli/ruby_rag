# frozen_string_literal: true

require "faraday"
require "json"

module Ai
  # Adaptador HTTP fino sobre a REST API do Qdrant. Cada serviço que
  # precisa de busca/armazenamento vetorial recebe uma instância disso
  # (ou de Ai::InMemoryVectorStore, nos testes) via injeção de
  # dependência — mesmo padrão de scope_builder: em VectorSearchService.
  class VectorStoreService
    Point = Data.define(:id, :vector, :payload, :score)

    class Error < StandardError; end
    class ConfigurationError < Error; end
    class InvalidRequestError < Error; end
    class TemporaryError < Error; end
    class InvalidResponseError < Error; end

    class << self
      # Instância padrão usada por quem não recebe vector_store: explicitamente
      # (ex.: callbacks de model). Testes substituem por
      # Ai::InMemoryVectorStore.new em test_helper.rb.
      def default
        @default ||= new
      end

      attr_writer :default
    end

    def initialize(
      url: Ai::Configuration.qdrant_url,
      api_key: Ai::Configuration.qdrant_api_key
    )
      @url = url
      @api_key = api_key
    end

    def ensure_collection!(collection:, size: Ai::Configuration::QDRANT_VECTOR_SIZE, distance: "Cosine")
      return if collection_exists?(collection)

      response = connection.put("collections/#{collection}") do |request|
        request.body = JSON.generate(
          vectors: { size: size, distance: distance }
        )
      end

      handle_http_status!(response)
    end

    def upsert(collection:, id:, vector:, payload: {})
      upsert_batch(
        collection: collection,
        points: [ { id: id, vector: vector, payload: payload } ]
      )
    end

    def upsert_batch(collection:, points:)
      return if points.empty?

      response = connection.put("collections/#{collection}/points?wait=true") do |request|
        request.body = JSON.generate(points: points.map { |point| normalize_point(point) })
      end

      handle_http_status!(response)
    end

    def search(collection:, vector:, limit:, ids: nil, with_vector: false)
      response = connection.post("collections/#{collection}/points/search") do |request|
        request.body = JSON.generate(
          {
            vector: vector,
            limit: limit,
            with_payload: true,
            with_vector: with_vector,
            filter: ids_filter(ids)
          }.compact
        )
      end

      handle_http_status!(response)

      parse_json(response.body).fetch("result", []).map do |item|
        build_point(item)
      end
    end

    def retrieve(collection:, ids:, with_vector: true)
      return [] if ids.empty?

      response = connection.post("collections/#{collection}/points") do |request|
        request.body = JSON.generate(
          ids: ids,
          with_payload: true,
          with_vector: with_vector
        )
      end

      handle_http_status!(response)

      parse_json(response.body).fetch("result", []).map do |item|
        build_point(item)
      end
    end

    def delete(collection:, ids: nil, filter: nil)
      return if ids.nil? && filter.nil?
      return if ids && ids.empty?

      response = connection.post("collections/#{collection}/points/delete?wait=true") do |request|
        request.body = JSON.generate(
          ids ? { points: ids } : { filter: match_filter(filter) }
        )
      end

      handle_http_status!(response)
    end

    private

    attr_reader :url, :api_key

    def collection_exists?(collection)
      response = connection.get("collections/#{collection}")

      response.status == 200
    end

    def normalize_point(point)
      point = point.to_h if point.is_a?(Point)

      {
        id: point.fetch(:id),
        vector: point.fetch(:vector),
        payload: point.fetch(:payload, {})
      }
    end

    def ids_filter(ids)
      return nil if ids.nil?

      { must: [ { has_id: ids } ] }
    end

    def match_filter(conditions)
      {
        must: conditions.map do |key, value|
          { key: key.to_s, match: { value: value } }
        end
      }
    end

    def build_point(item)
      Point.new(
        id: item["id"],
        vector: item["vector"],
        payload: item["payload"] || {},
        score: item["score"]
      )
    end

    def connection
      @connection ||= Faraday.new(url: url) do |faraday|
        faraday.options.open_timeout = Ai::Configuration.http_open_timeout
        faraday.options.timeout = Ai::Configuration.http_read_timeout
        faraday.headers["Content-Type"] = "application/json"
        faraday.headers["api-key"] = api_key if api_key.present?
        faraday.adapter Faraday.default_adapter
      end
    end

    def handle_http_status!(response)
      status = response.status.to_i

      return if status.between?(200, 299)

      body = parse_error_body(response.body)
      message = body.dig("status", "error").presence || "O Qdrant retornou HTTP #{status}"

      case status
      when 400, 404, 422
        raise InvalidRequestError, message
      when 401, 403
        raise ConfigurationError, message
      when 408, 429, 500..599
        raise TemporaryError, message
      else
        raise InvalidResponseError, message
      end
    end

    def parse_error_body(response_body)
      JSON.parse(response_body.to_s)
    rescue JSON::ParserError
      {}
    end

    def parse_json(response_body)
      body = JSON.parse(response_body.to_s)

      unless body.is_a?(Hash)
        raise InvalidResponseError, "A resposta do Qdrant não possui o formato esperado"
      end

      body
    rescue JSON::ParserError => error
      raise InvalidResponseError, "O Qdrant retornou um JSON inválido: #{error.message}"
    end
  end
end
