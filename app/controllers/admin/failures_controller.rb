# frozen_string_literal: true

class Admin::FailuresController < Admin::BaseController
  def index
    @documents = Document.where(status: "failed").order(updated_at: :desc)
    @stuck_processing_count = Document.where(status: "processing").count
  end

  def retry_all
    retried = Documents::RetryFailedIngestionsService.call

    record_audit_log(
      action: "failures.retry_all",
      details: { retried_count: retried.size, document_ids: retried.map { |item| item[:document_id] } }
    )

    redirect_to admin_failures_path, notice: "#{retried.size} ingestão(ões) reenfileirada(s)."
  end

  def reconcile_stale_processing
    reconciled = Documents::ReconcileStaleProcessingDocumentsService.call

    record_audit_log(
      action: "failures.reconcile_stale_processing",
      details: { reconciled_count: reconciled.size, document_ids: reconciled.map { |item| item[:document_id] } }
    )

    redirect_to admin_failures_path, notice: "#{reconciled.size} documento(s) preso(s) em processing movido(s) para failed."
  end
end
