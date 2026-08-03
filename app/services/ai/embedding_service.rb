require "net/http"
require "json"

module Ai
  class EmbeddingService
    class Error < StandardError; end
    class ConfigurationError < Error; end
    class AuthenticationError < Error; end
    class InvalidRequestError < Error; end
    class TemporaryError < Error; end
    class RateLimitError < TemporaryError; end
    class TimeoutError < TemporaryError; end
    class InvalidResponseError < Error; end

    def self.call(texts:)
      new(texts: texts).call
    end

    def initialize(texts:)
      @texts = normalize_texts(texts)
    end

    def call
      validate_configuration!
      validate_texts!

      response = perform_request

      parse_embeddings(response)
    rescue Net::OpenTimeout, Net::ReadTimeout => error
      raise TimeoutError,
            "Timeout ao solicitar embeddings: #{error.message}"
    rescue SocketError, Errno::ECONNRESET, Errno::ECONNREFUSED => error
      raise TemporaryError,
            "Falha temporária de conexão: #{error.message}"
    end

    private

    attr_reader :texts

    def normalize_texts(value)
      Array(value).map do |text|
        text.to_s.strip
      end
    end

    def validate_configuration!
      Ai::Configuration.validate!

      if api_key.blank?
        raise ConfigurationError,
              "A variável OPENAI_API_KEY não foi configurada."
      end
    end

    def validate_texts!
      if texts.empty?
        raise InvalidRequestError,
              "É necessário enviar pelo menos um texto."
      end

      empty_position = texts.index(&:blank?)

      return unless empty_position

      raise InvalidRequestError,
            "O texto da posição #{empty_position} está vazio."
    end

    def perform_request
      uri = URI(Ai::Configuration::EMBEDDING_ENDPOINT)

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{api_key}"
      request["Content-Type"] = "application/json"
      request.body = request_body.to_json

      Net::HTTP.start(
        uri.hostname,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: Ai::Configuration::HTTP_OPEN_TIMEOUT,
        read_timeout: Ai::Configuration::HTTP_READ_TIMEOUT
      ) do |http|
        http.request(request)
      end
    end

    def request_body
      {
        model: Ai::Configuration::EMBEDDING_MODEL,
        input: texts
      }
    end

    def parse_embeddings(response)
      body = parse_json(response.body)

      validate_http_response!(response, body)

      data = body["data"]

      unless data.is_a?(Array)
        raise InvalidResponseError,
              "A resposta não contém uma lista válida em data."
      end

      ordered_data = data.sort_by do |item|
        item.fetch("index")
      end

      embeddings = ordered_data.map do |item|
        item["embedding"]
      end

      validate_embeddings!(embeddings)

      embeddings
    end

    def validate_http_response!(response, body)
      status = response.code.to_i

      return if status.between?(200, 299)

      message =
        body.dig("error", "message") ||
        "A API de embeddings retornou HTTP #{status}."

      case status
      when 400, 404, 422
        raise InvalidRequestError, message
      when 401, 403
        raise AuthenticationError, message
      when 429
        raise RateLimitError, message
      when 500..599
        raise TemporaryError, message
      else
        raise InvalidResponseError, message
      end
    end

    def validate_embeddings!(embeddings)
      if embeddings.length != texts.length
        raise InvalidResponseError,
              "Quantidade de embeddings diferente da quantidade de textos. " \
              "Esperado: #{texts.length}; recebido: #{embeddings.length}."
      end

      embeddings.each_with_index do |embedding, index|
        unless embedding.is_a?(Array) && embedding.present?
          raise InvalidResponseError,
                "Embedding inválido na posição #{index}."
        end

        unless embedding.all? { |value| value.is_a?(Numeric) }
          raise InvalidResponseError,
                "Embedding da posição #{index} contém valores inválidos."
        end
      end
    end

    def parse_json(body)
      JSON.parse(body)
    rescue JSON::ParserError => error
      raise InvalidResponseError,
            "A API retornou um JSON inválido: #{error.message}"
    end

    def api_key
      ENV["OPENAI_API_KEY"]
    end
  end
end
