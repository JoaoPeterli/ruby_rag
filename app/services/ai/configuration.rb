# frozen_string_literal: true

require "uri"

module Ai
  class Configuration
    BASE_URL =
      ENV.fetch(
        "OPENAI_BASE_URL",
        "https://api.openai.com"
      )

    EMBEDDING_ENDPOINT =
      ENV.fetch(
        "OPENAI_EMBEDDING_ENDPOINT",
        "https://api.openai.com/v1/embeddings"
      )

    CHAT_COMPLETION_ENDPOINT =
      ENV.fetch(
        "OPENAI_CHAT_COMPLETION_ENDPOINT",
        "https://api.openai.com/v1/chat/completions"
      )

    EMBEDDING_MODEL =
      ENV.fetch(
        "OPENAI_EMBEDDING_MODEL",
        "text-embedding-3-small"
      )

    EMBEDDING_BATCH_SIZE =
      ENV.fetch(
        "OPENAI_EMBEDDING_BATCH_SIZE",
        100
      ).to_i

    CHAT_MODEL =
      ENV.fetch(
        "OPENAI_CHAT_MODEL",
        "gpt-4.1-mini"
      )

    CHAT_TEMPERATURE =
      ENV.fetch(
        "OPENAI_CHAT_TEMPERATURE",
        0.2
      ).to_f

    CHAT_MAX_COMPLETION_TOKENS =
      ENV.fetch(
        "OPENAI_CHAT_MAX_COMPLETION_TOKENS",
        800
      ).to_i

    HTTP_OPEN_TIMEOUT =
      ENV.fetch(
        "OPENAI_HTTP_OPEN_TIMEOUT",
        10
      ).to_i

    HTTP_READ_TIMEOUT =
      ENV.fetch(
        "OPENAI_HTTP_READ_TIMEOUT",
        60
      ).to_i

    QDRANT_URL =
      ENV.fetch(
        "QDRANT_URL",
        "http://localhost:6333"
      )

    QDRANT_API_KEY = ENV["QDRANT_API_KEY"]

    QDRANT_VECTOR_SIZE = 1536

    QDRANT_DOCUMENT_CHUNKS_COLLECTION = "document_chunks"

    QDRANT_SEMANTIC_CACHE_COLLECTION = "semantic_cache_entries"

    class ConfigurationError < StandardError; end

    class << self
      def api_key
        ENV["OPENAI_API_KEY"].to_s.strip
      end

      def base_url
        BASE_URL
      end

      def embedding_endpoint
        EMBEDDING_ENDPOINT
      end

      def chat_completion_endpoint
        CHAT_COMPLETION_ENDPOINT
      end

      def embedding_model
        EMBEDDING_MODEL
      end

      def chat_model
        CHAT_MODEL
      end

      def chat_temperature
        CHAT_TEMPERATURE
      end

      def chat_max_completion_tokens
        CHAT_MAX_COMPLETION_TOKENS
      end

      def http_open_timeout
        HTTP_OPEN_TIMEOUT
      end

      def http_read_timeout
        HTTP_READ_TIMEOUT
      end

      # Compatibilidade com o ChatCompletionService atual.
      def open_timeout
        HTTP_OPEN_TIMEOUT
      end

      def read_timeout
        HTTP_READ_TIMEOUT
      end

      def qdrant_url
        QDRANT_URL
      end

      def qdrant_api_key
        QDRANT_API_KEY
      end

      def validate!
        validate_api_key!
        validate_urls!
        validate_models!
        validate_temperature!
        validate_max_completion_tokens!
        validate_timeouts!

        true
      end

      private

      def validate_api_key!
        return if api_key.present?

        raise ConfigurationError,
              "OPENAI_API_KEY não foi configurada."
      end

      def validate_urls!
        validate_url!(
          base_url,
          "OPENAI_BASE_URL"
        )

        validate_url!(
          embedding_endpoint,
          "OPENAI_EMBEDDING_ENDPOINT"
        )

        validate_url!(
          chat_completion_endpoint,
          "OPENAI_CHAT_COMPLETION_ENDPOINT"
        )
      end

      def validate_models!
        if embedding_model.blank?
          raise ConfigurationError,
                "OPENAI_EMBEDDING_MODEL não foi configurado."
        end

        return if chat_model.present?

        raise ConfigurationError,
              "OPENAI_CHAT_MODEL não foi configurado."
      end

      def validate_temperature!
        return if chat_temperature.between?(0.0, 2.0)

        raise ConfigurationError,
              "OPENAI_CHAT_TEMPERATURE deve estar entre 0.0 e 2.0."
      end

      def validate_max_completion_tokens!
        return if chat_max_completion_tokens.positive?

        raise ConfigurationError,
              "OPENAI_CHAT_MAX_COMPLETION_TOKENS deve ser maior que zero."
      end

      def validate_timeouts!
        unless open_timeout.positive?
          raise ConfigurationError,
                "OPENAI_HTTP_OPEN_TIMEOUT deve ser maior que zero."
        end

        return if read_timeout.positive?

        raise ConfigurationError,
              "OPENAI_HTTP_READ_TIMEOUT deve ser maior que zero."
      end

      def validate_url!(url, variable)
        uri = URI.parse(url)

        valid =
          uri.is_a?(URI::HTTP) &&
          uri.host.present? &&
          %w[http https].include?(uri.scheme)

        return if valid

        raise ConfigurationError,
              "#{variable} precisa ser uma URL HTTP/HTTPS absoluta."
      rescue URI::InvalidURIError
        raise ConfigurationError,
              "#{variable} possui uma URL inválida."
      end
    end
  end
end
