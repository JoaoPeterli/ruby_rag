require "rails_helper"

RSpec.describe "Admin::Evaluations", type: :request do
  let!(:operator) { create(:account, operator: true) }

  before { sign_in_as(operator) }

  it "redirects to login when there is no session" do
    delete admin_session_path

    get admin_evaluations_path

    expect(response).to redirect_to(new_admin_session_path)
  end

  it "lists evaluation runs" do
    RagEvalRun.create!(cases_count: 0, started_at: Time.current, finished_at: Time.current)

    get admin_evaluations_path

    expect(response).to have_http_status(:success)
  end

  it "shows a run with its results" do
    run = RagEvalRun.create!(cases_count: 0, started_at: Time.current, finished_at: Time.current)

    get admin_evaluation_path(run)

    expect(response).to have_http_status(:success)
  end

  it "create triggers a new run with no active eval cases and redirects to it" do
    expect do
      post admin_evaluations_path
    end.to change(RagEvalRun, :count).by(1)

    run = RagEvalRun.order(:created_at).last
    expect(response).to redirect_to(admin_evaluation_path(run))
    expect(run.cases_count).to eq(0)
  end
end
