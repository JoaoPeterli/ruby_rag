# frozen_string_literal: true

module Documents
  module Pipeline
    class Context
      attr_accessor \
        :question,
        :search_query,
        :expanded_query,
        :queries,
        :query_embeddings,
        :metadata_filters,
        :metadata_extraction,
        :vector_results,
        :text_results,
        :hybrid_results,
        :merged_results,
        :reranked_results,
        :cross_encoder,
        :cross_encoder_results,
        :results,
        :parent_retrieval,
        :context_chunks,
        :context_compression,
        :compressed_chunks,
        :metadata,
        :metrics

      def initialize(question:)
        @question = question
        @search_query = question
        @queries = []
        @query_embeddings = {}

        @metadata_filters = Documents::MetadataFilters.empty
        @metadata_extraction = nil

        @vector_results = {}
        @text_results = {}
        @hybrid_results = {}

        @merged_results = []
        @reranked_results = []

        @cross_encoder = nil
        @cross_encoder_results = []

        @results = []

        @parent_retrieval = nil
        @context_chunks = []

        @context_compression = nil
        @compressed_chunks = []

        @metadata = {}
        @metrics = {}
      end
    end
  end
end
