require "rails_helper"

RSpec.describe Documents::ContextCompressionService do
  it "is an alias for Documents::ContextCompression::Service" do
    expect(Documents::ContextCompressionService).to equal(Documents::ContextCompression::Service)
  end
end
