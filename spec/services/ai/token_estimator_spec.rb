require "rails_helper"

RSpec.describe Ai::TokenEstimator do
  it "divides characters by the chars-per-token ratio" do
    expect(Ai::TokenEstimator.estimate("a" * 100)).to eq(25)
  end

  it "rounds up" do
    expect(Ai::TokenEstimator.estimate("ab")).to eq(1)
  end

  it "estimates zero tokens for blank text" do
    expect(Ai::TokenEstimator.estimate("")).to eq(0)
    expect(Ai::TokenEstimator.estimate(nil)).to eq(0)
  end

  it "characters_for is the inverse of estimate" do
    expect(Ai::TokenEstimator.characters_for(100)).to eq(400)
  end
end
