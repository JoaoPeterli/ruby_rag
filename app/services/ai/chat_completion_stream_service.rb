# frozen_string_literal: true

require "faraday"
require "json"

module Ai
  # Variante em streaming do ChatCompletionService: em vez de esperar a
  # resposta inteira, chama o bloco a cada pedaço de texto recebido e,
  # ao final, devolve o mesmo Ai::ChatCompletionService::Result de
  # sempre (com o texto completo já acumulado) — quem consome o
  # resultado final não precisa saber se veio de streaming ou não.
  class ChatCompletionStreamService
    class Error < StandardError; end
    class ConfigurationError < Error; end
    class InvalidRequestError < Error; end
    class AuthenticationError < Error; end
    class RateLimitError < Error; end
    class TemporaryError < Error; end
    class InvalidResponseError < Error; end

    def self.call(...)
      new(...).call
    end

    def initialize(
      messages:,
      model: Ai::Configuration.chat_model,
      temperature: Ai::Configuration.chat_temperature,
      max_completion_tokens: Ai::Configuration.chat_max_completion_tokens,
      &on_delta
    )
      @messages = messages
      @model = model.to_s.strip
      @temperature = temperature.to_f
      @max_completion_tokens = max_completion_tokens.to_i
      @on_delta = on_delta || proc {}
      @content = +""
      @final_model = nil
      @finish_reason = nil
      @usage = nil
    end

    def call
      started_at = monotonic_time

      validate!
      perform_request

      Ai::ChatCompletionService::Result.new(
        content: @content,
        model: @final_model || model,
        finish_reason: @finish_reason,
        usage: usage_hash,
        prompt_tokens: usage_hash[:prompt_tokens],
        completion_tokens: usage_hash[:completion_tokens],
        total_tokens: usage_hash[:total_tokens],
        duration_ms: elapsed_ms(started_at)
      )
    rescue Error
      raise
    rescue Faraday::TimeoutError => error
      raise TemporaryError,
            "A requisição para a OpenAI excedeu o tempo limite: #{error.message}"
    rescue Faraday::ConnectionFailed => error
      raise TemporaryError,
            "Não foi possível conectar à API da OpenAI: #{error.message}"
    end

    private

    attr_reader(
      :messages,
      :model,
      :temperature,
      :max_completion_tokens,
      :on_delta
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

      raise InvalidRequestError, "O modelo de chat não pode ficar vazio"
    end

    def validate_messages!
      unless messages.is_a?(Array) && messages.any?
        raise InvalidRequestError, "messages deve ser uma lista não vazia"
      end

      messages.each_with_index do |message, index|
        validate_message!(message: message, index: index)
      end
    end

    def validate_message!(message:, index:)
      unless message.respond_to?(:to_h)
        raise InvalidRequestError, "A mensagem #{index} precisa ser um Hash"
      end

      normalized_message = message.to_h.stringify_keys
      role = normalized_message["role"].to_s
      content = normalized_message["content"].to_s

      valid_roles = %w[system developer user assistant]

      unless valid_roles.include?(role)
        raise InvalidRequestError,
              "A mensagem #{index} possui role inválido: #{role.inspect}"
      end

      return if content.present?

      raise InvalidRequestError, "A mensagem #{index} não possui conteúdo"
    end

    def validate_temperature!
      return if temperature.between?(0.0, 2.0)

      raise InvalidRequestError, "temperature deve estar entre 0.0 e 2.0"
    end

    def validate_max_completion_tokens!
      return if max_completion_tokens.positive?

      raise InvalidRequestError,
            "max_completion_tokens deve ser maior que zero"
    end

    def perform_request
      buffer = +""

      response = connection.post(chat_completion_path) do |request|
        request.headers["Authorization"] = "Bearer #{Ai::Configuration.api_key}"
        request.headers["Content-Type"] = "application/json"
        request.headers["Accept"] = "text/event-stream"
        request.body = JSON.generate(request_payload)

        request.options.on_data = proc do |chunk, _bytes|
          buffer << chunk
          consume_buffer!(buffer)
        end
      end

      handle_http_status!(response.status, response) unless response.status.between?(200, 299)
    end

    def request_payload
      {
        model: model,
        messages: normalized_messages,
        temperature: temperature,
        max_completion_tokens: max_completion_tokens,
        stream: true,
        stream_options: { include_usage: true }
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

    def consume_buffer!(buffer)
      while (index = buffer.index("\n\n"))
        raw_event = buffer.slice!(0..index + 1)

        process_event(raw_event)
      end
    end

    def process_event(raw_event)
      raw_event.each_line do |line|
        line = line.strip

        next unless line.start_with?("data:")

        data = line.sub(/\Adata:\s*/, "")

        next if data == "[DONE]"

        handle_data_chunk(data)
      end
    end

    def handle_data_chunk(data)
      parsed = JSON.parse(data)

      choice = parsed["choices"]&.first

      if choice
        delta_content = choice.dig("delta", "content")

        if delta_content.present?
          @content << delta_content
          on_delta.call(delta_content)
        end

        @finish_reason = choice["finish_reason"] if choice["finish_reason"]
      end

      @final_model ||= parsed["model"]
      @usage = parsed["usage"] if parsed["usage"]
    rescue JSON::ParserError => error
      raise InvalidResponseError,
            "A API retornou um evento de streaming inválido: #{error.message}"
    end

    def usage_hash
      usage = @usage.is_a?(Hash) ? @usage : {}

      {
        prompt_tokens: usage["prompt_tokens"].to_i,
        completion_tokens: usage["completion_tokens"].to_i,
        total_tokens: usage["total_tokens"].to_i
      }
    end

    def connection
      @connection ||= Faraday.new(url: normalized_base_url) do |faraday|
        faraday.options.open_timeout = Ai::Configuration.open_timeout
        faraday.options.timeout = Ai::Configuration.read_timeout
        faraday.adapter Faraday.default_adapter
      end
    end

    def normalized_base_url
      "#{Ai::Configuration.base_url.delete_suffix('/')}/"
    end

    def chat_completion_path
      endpoint = URI.parse(Ai::Configuration.chat_completion_endpoint)
      path = endpoint.path.to_s.sub(%r{\A/}, "")

      endpoint.query.present? ? "#{path}?#{endpoint.query}" : path
    rescue URI::InvalidURIError => error
      raise ConfigurationError,
            "OPENAI_CHAT_COMPLETION_ENDPOINT inválido: #{error.message}"
    end

    def handle_http_status!(status, response)
      body = parse_error_body(response.body)

      api_message =
        body.dig("error", "message").presence ||
        "A API retornou HTTP #{status}"

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

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def elapsed_ms(started_at)
      ((monotonic_time - started_at) * 1_000).round
    end
  end
end
