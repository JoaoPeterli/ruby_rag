# frozen_string_literal: true

require "faraday"
require "json"

module Ai
  class ChatCompletionService
    class Error < StandardError; end
    class ConfigurationError < Error; end
    class InvalidRequestError < Error; end
    class AuthenticationError < Error; end
    class RateLimitError < Error; end
    class TemporaryError < Error; end
    class InvalidResponseError < Error; end

   Result = Data.define(
  :content,
  :model,
  :finish_reason,
  :usage,
  :prompt_tokens,
  :completion_tokens,
  :total_tokens,
  :duration_ms
)

    def self.call(
      messages:,
      model: Ai::Configuration.chat_model,
      temperature: Ai::Configuration.chat_temperature,
      max_completion_tokens: Ai::Configuration.chat_max_completion_tokens
    )
      new(
        messages: messages,
        model: model,
        temperature: temperature,
        max_completion_tokens: max_completion_tokens
      ).call
    end

    def initialize(
      messages:,
      model:,
      temperature:,
      max_completion_tokens:
    )
      @messages = messages
      @model = model.to_s.strip
      @temperature = temperature.to_f
      @max_completion_tokens = max_completion_tokens.to_i
    end

    def call
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  validate!

  response = perform_request
  body = parse_json(response.body)

  duration_ms = elapsed_milliseconds(started_at)

  result = build_result(
    body,
    duration_ms: duration_ms
  )

  log_success(result: result)

  result
rescue Error => error
  log_failure(
    error: error,
    started_at: started_at
  )

  raise
rescue Faraday::TimeoutError => error
  wrapped_error = TemporaryError.new(
    "A requisição para a OpenAI excedeu o tempo limite"
  )

  log_failure(
    error: wrapped_error,
    started_at: started_at,
    original_error: error
  )

  raise wrapped_error
rescue Faraday::ConnectionFailed => error
  wrapped_error = TemporaryError.new(
    "Não foi possível conectar à API da OpenAI"
  )

  log_failure(
    error: wrapped_error,
    started_at: started_at,
    original_error: error
  )

  raise wrapped_error
rescue JSON::ParserError => error
  wrapped_error = InvalidResponseError.new(
    "A API retornou um JSON inválido"
  )

  log_failure(
    error: wrapped_error,
    started_at: started_at,
    original_error: error
  )

  raise wrapped_error
end

    private

    attr_reader(
      :messages,
      :model,
      :temperature,
      :max_completion_tokens
    )

    def validate!
      Ai::Configuration.validate!

      validate_model!
      validate_messages!
      validate_temperature!
      validate_max_completion_tokens!
    rescue Ai::Configuration::ConfigurationError => error
      raise ConfigurationError, error.message
    end

    def validate_model!
      return if model.present?

      raise InvalidRequestError,
            "O modelo de chat não pode ficar vazio"
    end

    def validate_messages!
      unless messages.is_a?(Array) && messages.any?
        raise InvalidRequestError,
              "messages deve ser uma lista não vazia"
      end

      messages.each_with_index do |message, index|
        validate_message!(
          message: message,
          index: index
        )
      end
    end

    def validate_message!(message:, index:)
      unless message.respond_to?(:to_h)
        raise InvalidRequestError,
              "A mensagem #{index} precisa ser um Hash"
      end

      normalized_message = message.to_h.stringify_keys

      role = normalized_message["role"].to_s
      content = normalized_message["content"].to_s

      valid_roles = %w[
        system
        developer
        user
        assistant
      ]

      unless valid_roles.include?(role)
        raise InvalidRequestError,
              "A mensagem #{index} possui role inválido: #{role.inspect}"
      end

      return if content.present?

      raise InvalidRequestError,
            "A mensagem #{index} não possui conteúdo"
    end

    def validate_temperature!
      return if temperature.between?(0.0, 2.0)

      raise InvalidRequestError,
            "temperature deve estar entre 0.0 e 2.0"
    end

    def validate_max_completion_tokens!
      return if max_completion_tokens.positive?

      raise InvalidRequestError,
            "max_completion_tokens deve ser maior que zero"
    end

    def perform_request
      log_request

      response = connection.post(chat_completion_path) do |request|
        request.headers["Authorization"] =
          "Bearer #{Ai::Configuration.api_key}"

        request.headers["Content-Type"] =
          "application/json"

        request.body = JSON.generate(request_payload)
      end

      handle_http_status!(response)

      response
    end

    def request_payload
      {
        model: model,
        messages: normalized_messages,
        temperature: temperature,
        max_completion_tokens: max_completion_tokens
      }
    end

    def normalized_messages
      messages.map do |message|
        normalized_message = message.to_h.stringify_keys

        {
          role: normalized_message.fetch("role").to_s,
          content: normalized_message.fetch("content").to_s
        }
      end
    end

    def connection
      @connection ||= Faraday.new(
        url: normalized_base_url
      ) do |faraday|
        faraday.options.open_timeout =
          Ai::Configuration.open_timeout

        faraday.options.timeout =
          Ai::Configuration.read_timeout

        faraday.adapter Faraday.default_adapter
      end
    end

    def normalized_base_url
      "#{Ai::Configuration.base_url.delete_suffix("/")}/"
    end

    def chat_completion_path
      endpoint = URI.parse(
        Ai::Configuration.chat_completion_endpoint
      )

      path = endpoint.path.to_s.sub(%r{\A/}, "")

      if endpoint.query.present?
        "#{path}?#{endpoint.query}"
      else
        path
      end
    rescue URI::InvalidURIError => error
      raise ConfigurationError,
            "OPENAI_CHAT_COMPLETION_ENDPOINT inválido: #{error.message}"
    end

    def handle_http_status!(response)
      status = response.status.to_i

      return if status.between?(200, 299)

      body = parse_error_body(response.body)

      api_message =
        body.dig("error", "message").presence ||
        "A API retornou HTTP #{status}"

      error_type = body.dig("error", "type")
      error_code = body.dig("error", "code")
      error_param = body.dig("error", "param")

      Rails.logger.error(
        event: "openai_chat_completion_http_error",
        status: status,
        error_type: error_type,
        error_code: error_code,
        error_param: error_param,
        error_message: api_message
      )

      case status
      when 400, 404, 422
        raise InvalidRequestError, api_message
      when 401, 403
        raise AuthenticationError, api_message
      when 408
        raise TemporaryError, api_message
      when 429
        raise RateLimitError, api_message
      when 500..599
        raise TemporaryError, api_message
      else
        raise InvalidResponseError, api_message
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
        raise InvalidResponseError,
              "A resposta da API não possui o formato esperado"
      end

      body
    end

    def build_result(body, duration_ms:)
  choice = body.fetch("choices", []).first

  unless choice.is_a?(Hash)
    raise InvalidResponseError,
          "A resposta da API não possui choices"
  end

  content = choice.dig("message", "content").to_s.strip

  if content.blank?
    raise InvalidResponseError,
          "A API retornou uma resposta sem conteúdo"
  end

  usage = normalize_usage(body["usage"])

  Result.new(
    content: content,
    model: body["model"],
    finish_reason: choice["finish_reason"],
    usage: usage,
    prompt_tokens: usage[:prompt_tokens],
    completion_tokens: usage[:completion_tokens],
    total_tokens: usage[:total_tokens],
    duration_ms: duration_ms
  )
end

def log_success(result:)
  Rails.logger.info(
    event: "openai_chat_completion_completed",
    model: result.model,
    finish_reason: result.finish_reason,
    prompt_tokens: result.usage[:prompt_tokens],
    completion_tokens: result.usage[:completion_tokens],
    total_tokens: result.usage[:total_tokens],
        duration_ms: result.duration_ms

  )
end

def normalize_usage(raw_usage)
  usage = raw_usage.is_a?(Hash) ? raw_usage : {}

  {
    prompt_tokens: usage["prompt_tokens"].to_i,
    completion_tokens: usage["completion_tokens"].to_i,
    total_tokens: usage["total_tokens"].to_i
  }.freeze
end

    def log_request
      Rails.logger.info(
        event: "openai_chat_completion_started",
        model: model,
        messages_count: messages.size,
        message_roles: normalized_messages.pluck(:role),
        temperature: temperature,
        max_completion_tokens: max_completion_tokens
      )
    end

    def log_failure(
      error:,
      started_at:,
      original_error: nil
    )
      Rails.logger.error(
        event: "openai_chat_completion_failed",
        model: model,
        error_class: error.class.name,
        error_message: error.message,
        original_error_class: original_error&.class&.name,
        duration_ms: elapsed_milliseconds(started_at)
      )
    end

    def elapsed_milliseconds(started_at)
      finished_at =
        Process.clock_gettime(Process::CLOCK_MONOTONIC)

      ((finished_at - started_at) * 1000).round
    end
  end
end
