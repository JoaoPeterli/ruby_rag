require "rails_helper"

RSpec.describe "Admin::Failures", type: :request do
  let!(:operator) { create(:account, operator: true) }
  let!(:account) { create(:account) }

  before { sign_in_as(operator) }

  it "redirects to login when there is no session" do
    delete admin_session_path

    get admin_failures_path

    expect(response).to redirect_to(new_admin_session_path)
  end

  it "lists failed documents and the stuck-processing count" do
    create(:document, title: "Falhou", account: account, status: "failed", metadata: { "ingestion_error" => "deu ruim" })
    create(:document, title: "Preso", account: account, status: "processing", metadata: { "processing_last_attempt_at" => 1.hour.ago.iso8601 })

    get admin_failures_path

    expect(response).to have_http_status(:success)
    assert_select "td", text: "Falhou"
  end

  it "retry_all re-enqueues failed documents" do
    document = create(:document, title: "Falhou", account: account, status: "failed", metadata: { "ingestion_run_id" => "run-1" })

    stub_ingestion_job_enqueue do
      post retry_all_admin_failures_path
    end

    expect(response).to redirect_to(admin_failures_path)
    expect(document.reload.status).to eq("queued")

    log = AdminAuditLog.order(:created_at).last
    expect(log.action).to eq("failures.retry_all")
    expect(log.details["document_ids"]).to eq([ document.id ])
  end

  it "reconcile_stale_processing moves stuck documents to failed" do
    document = create(:document, title: "Preso", account: account, status: "processing", metadata: { "processing_last_attempt_at" => 1.hour.ago.iso8601 })

    post reconcile_stale_processing_admin_failures_path

    expect(response).to redirect_to(admin_failures_path)
    expect(document.reload.status).to eq("failed")

    log = AdminAuditLog.order(:created_at).last
    expect(log.action).to eq("failures.reconcile_stale_processing")
  end
end
