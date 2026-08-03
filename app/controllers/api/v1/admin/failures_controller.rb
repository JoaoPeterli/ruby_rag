# frozen_string_literal: true

module Api
  module V1
    module Admin
      class FailuresController < BaseController
        def index
          documents = Document.where(status: "failed").order(updated_at: :desc)

          render json: {
            documents: documents.map { |document| serialize(document) }
          }
        end

        def retry_all
          retried = Documents::RetryFailedIngestionsService.call

          render json: { retried: retried }
        rescue Documents::RetryFailedIngestionsService::Error => error
          render json: { error: error.message }, status: :unprocessable_entity
        end

        private

        def serialize(document)
          metadata = document.metadata.to_h

          {
            id: document.id,
            title: document.title,
            ingestion_error_class: metadata["ingestion_error_class"],
            ingestion_error: metadata["ingestion_error"],
            ingestion_failed_at: metadata["ingestion_failed_at"],
            ingestion_attempts: metadata["ingestion_attempts"]
          }
        end
      end
    end
  end
end
