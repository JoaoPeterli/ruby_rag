# frozen_string_literal: true

class Portal::DocumentsController < Portal::BaseController
  include Paginatable

  before_action :require_upload_enabled!, only: [ :new, :create ]

  def index
    scope = current_user.account.documents.order(created_at: :desc)

    @status_filter = params[:status]
    scope = scope.where(status: @status_filter) if @status_filter.present?

    @total_count = scope.count
    @documents = scope.limit(PER_PAGE).offset(page_offset)
  end

  def show
    @document = current_user.account.documents.find(params[:id])
    @chunks = @document.document_chunks.ordered
  end

  def new
    @document = current_user.account.documents.new
  end

  def create
    Documents::UploadDocumentService.call(
      account: current_user.account,
      title: params.dig(:document, :title),
      file: params.dig(:document, :source_file),
      ramo: params.dig(:document, :ramo),
      seguradora: params.dig(:document, :seguradora),
      cliente: params.dig(:document, :cliente),
      tipo_documento: params.dig(:document, :tipo_documento),
      vigencia_ano: params.dig(:document, :vigencia_ano)
    )

    redirect_to portal_documents_path, notice: "Documento enviado. O processamento roda em segundo plano."
  rescue Documents::UploadDocumentService::Error => error
    flash.now[:alert] = error.message
    @document = current_user.account.documents.new
    render :new, status: :unprocessable_entity
  end

  private

  def upload_enabled?
    ENV.fetch("DOCUMENT_UPLOAD_ENABLED", "false") == "true"
  end
  helper_method :upload_enabled?

  def require_upload_enabled!
    return if upload_enabled?

    redirect_to portal_documents_path, alert: "O envio de documentos ainda não está disponível."
  end
end
