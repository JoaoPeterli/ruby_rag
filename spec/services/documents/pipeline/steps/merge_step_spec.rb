require "rails_helper"

RSpec.describe Documents::Pipeline::Steps::MergeStep do
  def fake_merger(&on_call)
    Class.new do
      define_singleton_method(:call) do |**kwargs|
        on_call.call(kwargs)
      end
    end
  end

  it "builds query_results from context.queries and context.hybrid_results, keyed by position" do
    context = Documents::Pipeline::Context.new(question: "pergunta")
    context.queries = [ "pergunta", "pergunta expandida" ]
    context.hybrid_results = {
      "pergunta" => [ :result_a ],
      "pergunta expandida" => [ :result_b, :result_c ]
    }
    context.metadata[:multi_query_result_limit] = 40

    received = nil
    merger = fake_merger { |kwargs| received = kwargs; [ :merged ] }

    Documents::Pipeline::Steps::MergeStep.call(
      context: context,
      multi_query_result_merger: merger
    )

    expect(received[:limit]).to eq(40)
    expect(received[:query_results]).to eq(
      [
        { query: "pergunta", query_position: 1, results: [ :result_a ] },
        { query: "pergunta expandida", query_position: 2, results: [ :result_b, :result_c ] }
      ]
    )
  end

  it "defaults to an empty results array for a query missing from hybrid_results" do
    context = Documents::Pipeline::Context.new(question: "pergunta")
    context.queries = [ "pergunta" ]
    context.hybrid_results = {}
    context.metadata[:multi_query_result_limit] = 10

    received = nil
    merger = fake_merger { |kwargs| received = kwargs; [] }

    Documents::Pipeline::Steps::MergeStep.call(context: context, multi_query_result_merger: merger)

    expect(received[:query_results].first[:results]).to eq([])
  end

  it "assigns the merger's return value to context.merged_results and records the metric" do
    context = Documents::Pipeline::Context.new(question: "pergunta")
    context.queries = [ "pergunta" ]
    context.hybrid_results = { "pergunta" => [] }
    context.metadata[:multi_query_result_limit] = 10

    merger = fake_merger { |_kwargs| [ :merged_result_1, :merged_result_2 ] }

    Documents::Pipeline::Steps::MergeStep.call(context: context, multi_query_result_merger: merger)

    expect(context.merged_results).to eq([ :merged_result_1, :merged_result_2 ])
    expect(context.metrics[:merge]).to be_a(Numeric)
  end
end
