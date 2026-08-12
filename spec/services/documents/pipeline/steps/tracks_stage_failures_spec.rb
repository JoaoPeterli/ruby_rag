require "rails_helper"

RSpec.describe Documents::Pipeline::Steps::TracksStageFailures do
  # Mixin puro, sem estado próprio: exercitamos o contrato incluindo-o
  # numa subclasse anônima de Step, do mesmo jeito que os steps reais
  # (MetadataExtractionStep, MultiQueryStep, etc.) o incluem.
  def step_class
    Class.new(Documents::Pipeline::Step) do
      include Documents::Pipeline::Steps::TracksStageFailures

      def call(stage:, error:)
        record_stage_failure(stage: stage, error: error)
      end
    end
  end

  it "appends a structured failure entry with stage, error class and message" do
    context = Documents::Pipeline::Context.new(question: "pergunta")

    step_class.new(context: context).call(
      stage: "meu_estagio",
      error: ArgumentError.new("algo deu errado")
    )

    expect(context.metadata[:stage_failures].size).to eq(1)

    entry = context.metadata[:stage_failures].first
    expect(entry[:stage]).to eq("meu_estagio")
    expect(entry[:error_class]).to eq("ArgumentError")
    expect(entry[:error_message]).to eq("algo deu errado")
  end

  it "accumulates multiple failures instead of overwriting" do
    context = Documents::Pipeline::Context.new(question: "pergunta")
    step = step_class.new(context: context)

    step.call(stage: "estagio_1", error: StandardError.new("primeiro"))
    step.call(stage: "estagio_2", error: StandardError.new("segundo"))

    expect(context.metadata[:stage_failures].size).to eq(2)
    expect(context.metadata[:stage_failures].map { |entry| entry[:stage] }).to eq([ "estagio_1", "estagio_2" ])
  end
end
