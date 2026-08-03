# frozen_string_literal: true

module Documents
  class FullTextSearchService
    DEFAULT_LIMIT = 20

    Result = Data.define(
      :chunk,
      :text_score,
      :position
    )

    class Error < StandardError; end
    class InvalidQueryError < Error; end
    class InvalidLimitError < Error; end

    def self.call(...)
      new(...).call
    end

    def initialize(
      query:,
      limit: DEFAULT_LIMIT,
      scope: DocumentChunk.all,
      filters: Documents::MetadataFilters.empty,
      scope_builder: Documents::MetadataScopeBuilder
    )
      @query = query
      @limit = limit
      @scope = scope
      @filters = filters
      @scope_builder = scope_builder
    end

    def call
      validate!

      retrieve_results.each_with_index.map do |chunk, index|
        Result.new(
          chunk: chunk,
          text_score: chunk.text_score.to_f,
          position: index + 1
        )
      end
    rescue ActiveRecord::ActiveRecordError => error
      raise Error,
            "Não foi possível realizar a busca textual: #{error.message}"
    end

    private

    attr_reader :query, :limit, :scope, :filters, :scope_builder

    def validate!
      validate_query!
      validate_limit!
    end

    def validate_query!
      return if query.is_a?(String) && query.strip.present?

      raise InvalidQueryError,
            "A consulta deve ser uma string não vazia"
    end

    def validate_limit!
      return if limit.is_a?(Integer) && limit.positive?

      raise InvalidLimitError,
            "limit deve ser um número inteiro maior que zero"
    end

    def retrieve_results
      filtered_scope
        .select(
          "document_chunks.*",
          <<~SQL.squish
            ts_rank_cd(
              document_chunks.search_vector,
              websearch_to_tsquery(
                'portuguese',
                #{connection.quote(normalized_query)}
              )
            ) AS text_score
          SQL
        )
        .where(
          <<~SQL.squish
            document_chunks.search_vector @@
            websearch_to_tsquery(
              'portuguese',
              #{connection.quote(normalized_query)}
            )
          SQL
        )
        .order(Arel.sql("text_score DESC"))
        .limit(limit)
    end

    def normalized_query
      @normalized_query ||= query.strip
    end

    def filtered_scope
      scope_builder.call(
        scope: scope,
        filters: filters
      )
    end

    def connection
      DocumentChunk.connection
    end
  end
end
