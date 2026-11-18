require "rails_helper"

# Uma fila usada por um job mas ausente do config/sidekiq.yml nunca é
# consumida: o job fica parado no Redis pra sempre (já aconteceu com
# document_ocr, deixando uploads presos em "uploaded").
RSpec.describe "config/sidekiq.yml" do
  it "listens to every queue declared by the app's jobs" do
    config = YAML.load_file(Rails.root.join("config/sidekiq.yml"))
    configured = config.fetch(:queues).map { |queue| Array(queue).first.to_s }

    Rails.application.eager_load!
    used = ApplicationJob.descendants.map { |job| job.new.queue_name.to_s }.uniq

    expect(used - configured).to be_empty
  end
end
