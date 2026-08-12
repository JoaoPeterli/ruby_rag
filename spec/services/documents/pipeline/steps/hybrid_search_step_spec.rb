require "rails_helper"

RSpec.describe Documents::Pipeline::Steps::HybridSearchStep do
  def fake_service(&on_call)
    Class.new do
      define_singleton_method(:call) { |**kwargs| on_call.call(kwargs) }
    end
  end

  def base_context(filters: Documents::MetadataFilters.empty)
    context = Documents::Pipeline::Context.new(question: "pergunta")
    context.query_embeddings = { "pergunta" => Array.new(4, 0.1) }
    context.metadata[:candidate_limit] = 20
    context.metadata[:minimum_similarity] = 0.5
    context.metadata_filters = filters
    context
  end

  def account_scope_builder_stub
    fake_service { |**_kwargs| :account_scope }
  end

  it "runs vector, text and hybrid search per query and stores the results keyed by query" do
    context = base_context

    Documents::Pipeline::Steps::HybridSearchStep.call(
      context: context,
      vector_search_service: fake_service { |_kwargs| [ :vector_result ] },
      full_text_search_service: fake_service { |_kwargs| [ :text_result ] },
      hybrid_search_service: fake_service { |_kwargs| [ :hybrid_result ] },
      account_scope_builder: account_scope_builder_stub
    )

    expect(context.vector_results["pergunta"]).to eq([ :vector_result ])
    expect(context.text_results["pergunta"]).to eq([ :text_result ])
    expect(context.hybrid_results["pergunta"]).to eq([ :hybrid_result ])
    expect(context.metrics[:hybrid_search]).to be_a(Numeric)
  end

  it "passes candidate_limit, minimum_similarity and filters through to the vector and text searches" do
    context = base_context

    received_vector = nil
    received_text = nil

    Documents::Pipeline::Steps::HybridSearchStep.call(
      context: context,
      vector_search_service: fake_service { |kwargs| received_vector = kwargs; [] },
      full_text_search_service: fake_service { |kwargs| received_text = kwargs; [] },
      hybrid_search_service: fake_service { |_kwargs| [] },
      account_scope_builder: account_scope_builder_stub
    )

    expect(received_vector[:candidate_limit]).to eq(20)
    expect(received_vector[:minimum_similarity]).to eq(0.5)
    expect(received_vector[:filters]).to eq(context.metadata_filters)
    expect(received_text[:limit]).to eq(20)
    expect(received_text[:filters]).to eq(context.metadata_filters)
  end

  it "retries without metadata filters when the filtered search finds nothing" do
    filters = Documents::MetadataFilters.new(
      ramo: "auto", seguradora: nil, cliente: nil, tipo_documento: nil, vigencia_ano: nil, metadata: {}
    )
    context = base_context(filters: filters)

    call_count = 0
    hybrid_service = fake_service do |_kwargs|
      call_count += 1
      call_count == 1 ? [] : [ :hybrid_result_unfiltered ]
    end

    Documents::Pipeline::Steps::HybridSearchStep.call(
      context: context,
      vector_search_service: fake_service { |_kwargs| [] },
      full_text_search_service: fake_service { |_kwargs| [] },
      hybrid_search_service: hybrid_service,
      account_scope_builder: account_scope_builder_stub,
      logger: Logger.new(File::NULL)
    )

    expect(call_count).to eq(2)
    expect(context.metadata_filters.empty?).to be_truthy
    expect(context.hybrid_results["pergunta"]).to eq([ :hybrid_result_unfiltered ])
    expect(context.metadata[:stage_failures].size).to eq(1)
    expect(context.metadata[:stage_failures].first[:stage]).to eq("hybrid_search")
  end

  it "does not retry when there were no metadata filters to drop in the first place" do
    context = base_context(filters: Documents::MetadataFilters.empty)

    call_count = 0
    hybrid_service = fake_service do |_kwargs|
      call_count += 1
      []
    end

    Documents::Pipeline::Steps::HybridSearchStep.call(
      context: context,
      vector_search_service: fake_service { |_kwargs| [] },
      full_text_search_service: fake_service { |_kwargs| [] },
      hybrid_search_service: hybrid_service,
      account_scope_builder: account_scope_builder_stub
    )

    expect(call_count).to eq(1)
    expect(context.metadata[:stage_failures]).to be_nil
  end
end
