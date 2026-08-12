# frozen_string_literal: true

# queue_adapter é :sidekiq no app inteiro (não só produção — ver
# config/application.rb), então qualquer perform_later real precisa de
# Redis. Usado onde o código sob teste dispara reingestão (ex.: retry_all).
module JobStubHelper
  def stub_ingestion_job_enqueue
    fake_job = Struct.new(:job_id).new(SecureRandom.uuid)

    allow(Documents::IngestionJob).to receive(:perform_later).and_return(fake_job)

    yield
  end
end

RSpec.configure do |config|
  config.include JobStubHelper
end
