# frozen_string_literal: true

module Documents
  class MetadataScopeBuilder
    class Error < StandardError; end
    class InvalidScopeError < Error; end
    class InvalidFiltersError < Error; end

    def self.call(...)
      new(...).call
    end

    def initialize(
      scope: DocumentChunk.all,
      filters: MetadataFilters.empty
    )
      @scope = scope
      @filters = filters
    end

    def call
      validate!

      filtered_scope = scope.joins(:document)

      filtered_scope =
        apply_case_insensitive_filter(
          filtered_scope,
          column: "documents.ramo",
          value: filters.ramo
        )

      filtered_scope =
        apply_case_insensitive_filter(
          filtered_scope,
          column: "documents.seguradora",
          value: filters.seguradora
        )

      filtered_scope =
        apply_case_insensitive_filter(
          filtered_scope,
          column: "documents.cliente",
          value: filters.cliente
        )

      filtered_scope =
        apply_case_insensitive_filter(
          filtered_scope,
          column: "documents.tipo_documento",
          value: filters.tipo_documento
        )

      if filters.vigencia_ano.present?
        filtered_scope =
          filtered_scope.where(
            documents: {
              vigencia_ano: filters.vigencia_ano
            }
          )
      end

      if filters.metadata.present?
        filtered_scope =
          filtered_scope.where(
            "documents.metadata @> ?::jsonb",
            filters.metadata.to_json
          )
      end

      filtered_scope
    end

    private

    attr_reader :scope, :filters

    def validate!
      unless scope.respond_to?(:where)
        raise InvalidScopeError,
              "scope deve ser uma relação ActiveRecord"
      end

      return if filters.is_a?(Documents::MetadataFilters)

      raise InvalidFiltersError,
            "filters deve ser Documents::MetadataFilters"
    end

    def apply_case_insensitive_filter(
      current_scope,
      column:,
      value:
    )
      return current_scope if value.blank?

      current_scope.where(
        "LOWER(#{column}) = LOWER(?)",
        value.to_s.strip
      )
    end
  end
end
