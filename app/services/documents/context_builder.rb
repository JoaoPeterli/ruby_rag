module Documents
  class ContextBuilder
    DEFAULT_MAX_CHARACTERS = 12_000
    DEFAULT_SEPARATOR = "\n\n---\n\n"

    MIN_OVERLAP_CHARACTERS = 30
    MAX_OVERLAP_CHARACTERS = 500

    MIN_TRUNCATED_CONTENT_CHARACTERS = 150
    TRUNCATION_SUFFIX = " […]"

    Result = Data.define(
      :context,
      :sources,
      :chunks_count,
      :characters_count,
      :truncated,
      :input_chunks_count,
      :discarded_chunks_count
    )

    ProcessedChunk = Data.define(
      :result,
      :content,
      :overlap_removed,
      :truncated
    )

    class Error < StandardError; end
    class InvalidResultsError < Error; end
    class InvalidMaxCharactersError < Error; end

    def self.call(
      results:,
      max_characters: DEFAULT_MAX_CHARACTERS
    )
      new(
        results: results,
        max_characters: max_characters
      ).call
    end

    def initialize(results:, max_characters:)
      @results = Array(results)
      @max_characters = max_characters
    end

    def call
      validate!

      started_at = monotonic_time

      unique = unique_results
      ordered = order_results(unique)
      built = build_context(ordered)

      result =
        Result.new(
          context: built.fetch(:context),
          sources: built.fetch(:sources),
          chunks_count: built.fetch(:sources).length,
          characters_count: built.fetch(:context).length,
          truncated: built.fetch(:truncated),
          input_chunks_count: results.length,
          discarded_chunks_count:
            results.length -
            built.fetch(:sources).length
        )

      log_build(
        result: result,
        unique_results_count: unique.length,
        started_at: started_at
      )

      result
    end

    private

    attr_reader :results,
                :max_characters

    def validate!
      validate_results!
      validate_max_characters!
    end

    def validate_results!
      return if results.all? do |result|
        result.is_a?(
          Documents::VectorSearchResult
        )
      end

      raise InvalidResultsError,
            "Todos os resultados precisam ser VectorSearchResult."
    end

    def validate_max_characters!
      return if max_characters.is_a?(Integer) &&
                max_characters.positive?

      raise InvalidMaxCharactersError,
            "max_characters precisa ser um inteiro maior que zero."
    end

    def unique_results
      seen = {}

      results.each_with_object([]) do |result, collection|
        key =
          clean_content(
            result.content
          ).downcase

        next if key.blank?
        next if seen[key]

        seen[key] = true
        collection << result
      end
    end

    def order_results(collection)
      collection
        .group_by(&:document_id)
        .flat_map do |_document_id, document_results|
          document_results.sort_by(&:position)
        end
    end

    def process_chunk(result, previous_content)
      content = clean_content(result.content)

      processed_content, overlap_removed =
        remove_overlap(
          previous_content,
          content
        )

      ProcessedChunk.new(
        result: result,
        content: processed_content,
        overlap_removed: overlap_removed,
        truncated: false
      )
    end

    def remove_overlap(previous_content, current_content)
      return [ current_content, 0 ] if previous_content.blank?
      return [ current_content, 0 ] if current_content.blank?

      max_size = [
        previous_content.length,
        current_content.length,
        MAX_OVERLAP_CHARACTERS
      ].min

      max_size.downto(MIN_OVERLAP_CHARACTERS) do |size|
        previous_suffix =
          previous_content[-size, size]

        current_prefix =
          current_content[0, size]

        next unless equivalent_text?(
          previous_suffix,
          current_prefix
        )

        cleaned =
          current_content[size..]
            .to_s
            .strip

        return [ cleaned, size ]
      end

      [ current_content, 0 ]
    end

    def equivalent_text?(left, right)
      normalize_for_comparison(left) ==
        normalize_for_comparison(right)
    end

    def normalize_for_comparison(text)
      text
        .to_s
        .gsub(/\s+/, " ")
        .strip
        .downcase
    end

    def clean_content(content)
      content
        .to_s
        .gsub(/\s+/, " ")
        .strip
    end

    def build_context(collection)
      sections = []
      sources = []
      current_size = 0
      truncated = false
      previous_content = nil

      collection.each do |result|
        source_number = sources.length + 1

        processed_chunk =
          process_chunk(
            result,
            previous_content
          )

        next if processed_chunk.content.blank?

        separator_size =
          sections.empty? ? 0 : DEFAULT_SEPARATOR.length

        full_section =
          format_source(
            processed_chunk,
            source_number
          )

        projected_size =
          current_size +
          separator_size +
          full_section.length

        if projected_size <= max_characters
          sections << full_section

          sources <<
            build_source_metadata(
              processed_chunk,
              source_number
            )

          current_size = projected_size
          previous_content = clean_content(result.content)

          next
        end

        available_characters =
          max_characters -
          current_size -
          separator_size

        truncated_chunk =
          truncate_processed_chunk(
            processed_chunk,
            source_number,
            available_characters
          )

        if truncated_chunk
          truncated_section =
            format_source(
              truncated_chunk,
              source_number
            )

          sections << truncated_section

          sources <<
            build_source_metadata(
              truncated_chunk,
              source_number
            )
        end

        truncated = true
        break
      end

      {
        context: sections.join(DEFAULT_SEPARATOR),
        sources: sources,
        truncated: truncated
      }
    end

    def truncate_processed_chunk(
      processed_chunk,
      source_number,
      available_characters
    )
      header =
        format_source_header(
          processed_chunk,
          source_number
        )

      fixed_size =
        header.length +
        2 +
        TRUNCATION_SUFFIX.length

      available_content_size =
        available_characters - fixed_size

      return if available_content_size <
                MIN_TRUNCATED_CONTENT_CHARACTERS

      truncated_content =
        truncate_at_word_boundary(
          processed_chunk.content,
          available_content_size
        )

      return if truncated_content.length <
                MIN_TRUNCATED_CONTENT_CHARACTERS

      ProcessedChunk.new(
        result: processed_chunk.result,
        content: "#{truncated_content}#{TRUNCATION_SUFFIX}",
        overlap_removed: processed_chunk.overlap_removed,
        truncated: true
      )
    end

    def truncate_at_word_boundary(
      content,
      maximum_length
    )
      return content if content.length <= maximum_length

      candidate = content[0, maximum_length]
      last_space = candidate.rindex(" ")

      return candidate if last_space.nil?

      candidate[0, last_space].strip
    end

    def format_source(processed_chunk, source_number)
      header =
        format_source_header(
          processed_chunk,
          source_number
        )

      "#{header}\n\n#{processed_chunk.content}"
    end

    def format_source_header(
      processed_chunk,
      source_number
    )
      result = processed_chunk.result

      <<~TEXT.strip
        [FONTE #{source_number}]
        Documento: #{result.document_id}
        Chunk: #{result.chunk_id}
        Posição: #{result.position}
        Relevância: #{format_score(result.score)}
      TEXT
    end

    def format_score(score)
      format("%.4f", score.to_f)
    end

    def build_source_metadata(
      processed_chunk,
      source_number
    )
      result = processed_chunk.result

      {
        source_number: source_number,
        chunk_id: result.chunk_id,
        document_id: result.document_id,
        position: result.position,
        score: result.score,
        distance: result.distance,
        overlap_removed: processed_chunk.overlap_removed,
        truncated: processed_chunk.truncated,
        included_characters: processed_chunk.content.length,
        metadata: result.metadata
      }
    end

    def log_build(
      result:,
      unique_results_count:,
      started_at:
    )
      Rails.logger.info(
        event: "document_context_built",
        input_results_count: result.input_chunks_count,
        unique_results_count: unique_results_count,
        chunks_count: result.chunks_count,
        discarded_chunks_count: result.discarded_chunks_count,
        characters_count: result.characters_count,
        max_characters: max_characters,
        truncated: result.truncated,
        duration_ms: elapsed_milliseconds(started_at)
      )
    end

    def monotonic_time
      Process.clock_gettime(
        Process::CLOCK_MONOTONIC
      )
    end

    def elapsed_milliseconds(started_at)
      finished_at = monotonic_time

      ((finished_at - started_at) * 1_000).round
    end
  end
end
