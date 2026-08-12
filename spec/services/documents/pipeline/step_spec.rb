require "rails_helper"

RSpec.describe Documents::Pipeline::Step do
  it "self.call builds an instance with the given context and delegates to #call, which subclasses must implement" do
    expect do
      Documents::Pipeline::Step.call(context: Object.new)
    end.to raise_error(NoMethodError)
  end

  it "elapsed_ms measures a positive, rounded duration since the given monotonic start" do
    subclass = Class.new(Documents::Pipeline::Step) do
      def call
        started_at = monotonic_time
        elapsed_ms(started_at)
      end
    end

    elapsed = subclass.call(context: nil)

    expect(elapsed).to be_a(Float)
    expect(elapsed).to be >= 0.0
    expect(elapsed.round(2)).to eq(elapsed)
  end
end
