# frozen_string_literal: true

module Api
  module V1
    module Admin
      class DocumentsController < BaseController
        DEFAULT_LIMIT = 25
        MAX_LIMIT = 100

        def index
          documents = Document
            .order(created_at: :desc)
            .limit(limit_param)
            .offset(params[:offset].to_i)

          documents = documents.where(status: params[:status]) if params[:status].present?

          render json: {
            documents: documents.map { |document| serialize(document) },
            total_count: Document.count
          }
        end

        def show
          document = Document.find(params[:id])

          render json: serialize(document, include_chunks: true)
        end

        private

        def limit_param
          [ params.fetch(:limit, DEFAULT_LIMIT).to_i, MAX_LIMIT ].min.clamp(1, MAX_LIMIT)
        end

        def serialize(document, include_chunks: false)
          data = {
            id: document.id,
            title: document.title,
            status: document.status,
            ramo: document.ramo,
            seguradora: document.seguradora,
            cliente: document.cliente,
            tipo_documento: document.tipo_documento,
            vigencia_ano: document.vigencia_ano,
            content_version: document.content_version,
            content_hash: document.content_hash,
            chunks_count: document.document_chunks.size,
            ingestion_error: document.metadata.to_h["ingestion_error"],
            created_at: document.created_at,
            updated_at: document.updated_at
          }

          data[:chunks] = document.document_chunks.ordered.map { |chunk| serialize_chunk(chunk) } if include_chunks

          data
        end

        def serialize_chunk(chunk)
          {
            id: chunk.id,
            position: chunk.position,
            content: chunk.content.truncate(200),
            prompt_injection_suspicious: chunk.metadata["prompt_injection_suspicious"],
            prompt_injection_risk_score: chunk.metadata["prompt_injection_risk_score"]
          }
        end
      end
    end
  end
end
