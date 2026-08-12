require "rails_helper"

RSpec.describe Documents::Pipeline::Steps::Answering::LogsStageFailure do
  def including_class
    @including_class ||= Class.new do
      include Documents::Pipeline::Steps::Answering::LogsStageFailure
      public :log_stage_failure
    end
  end

  it "logs a structured warning with the stage and error details" do
    logged = nil
    fake_logger = Object.new
    fake_logger.define_singleton_method(:warn) { |payload| logged = payload }

    original_logger = Rails.logger
    Rails.logger = fake_logger
    begin
      including_class.new.log_stage_failure(stage: "hallucination_check", error: StandardError.new("falha ao verificar"))
    ensure
      Rails.logger = original_logger
    end

    expect(logged[:event]).to eq("document_question_answering_stage_failure")
    expect(logged[:stage]).to eq("hallucination_check")
    expect(logged[:error_class]).to eq("StandardError")
    expect(logged[:error_message]).to eq("falha ao verificar")
  end
end
