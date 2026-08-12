require "rails_helper"

RSpec.describe Documents::Pipeline::Pipeline do
  def recording_step(name)
    Class.new do
      define_singleton_method(:call) do |context:|
        context.metadata[:ran] ||= []
        context.metadata[:ran] << name
      end
    end
  end

  it "runs each step in order, threading the same context through all of them" do
    context = Documents::Pipeline::Context.new(question: "pergunta")

    result = Documents::Pipeline::Pipeline.call(
      context: context,
      steps: [ recording_step(:first), recording_step(:second), recording_step(:third) ]
    )

    expect(context.metadata[:ran]).to eq([ :first, :second, :third ])
    expect(result).to equal(context)
  end

  it "returns the context untouched when there are no steps" do
    context = Documents::Pipeline::Context.new(question: "pergunta")

    result = Documents::Pipeline::Pipeline.call(context: context, steps: [])

    expect(result).to equal(context)
    expect(context.metadata[:ran]).to be_nil
  end
end
