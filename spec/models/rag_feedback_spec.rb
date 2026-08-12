require "rails_helper"

RSpec.describe RagFeedback do
  it "only accepts positive or negative ratings" do
    valid = build(:rag_feedback, rating: "positive")
    invalid = build(:rag_feedback, rating: "meh")

    expect(valid).to be_valid
    expect(invalid).not_to be_valid
    expect(invalid.errors.attribute_names).to include(:rating)
  end

  it "does not require a reason" do
    feedback = build(:rag_feedback, rating: "negative", reason: nil)

    expect(feedback).to be_valid
  end
end
